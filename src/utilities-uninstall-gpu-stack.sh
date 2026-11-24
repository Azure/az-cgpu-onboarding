#!/usr/bin/env bash

## Undo NCC src steps 1-3 without reverting step 0 kernel preparation.
## All NVIDIA driver and DCGM package versions are included in cleanup.
## Cleanup is non-interactive; container data and shared prerequisites are kept.
##
## Examples:
##      sudo bash utilities-uninstall-gpu-stack.sh --dry-run
##      sudo bash utilities-uninstall-gpu-stack.sh
##      sudo bash utilities-uninstall-gpu-stack.sh --remove-miniconda

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_CONFIG="/etc/docker/daemon.json"
# Common APT settings: non-interactive debconf, lock timeout, retries, and network timeouts.
APT_ENV=(DEBIAN_FRONTEND=noninteractive)
APT_OPTS=(-o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)
DRY_RUN=0
REMOVE_MINICONDA=0
PACKAGES=()

usage() {
    cat <<'EOF'
Usage: sudo bash utilities-uninstall-gpu-stack.sh [OPTIONS]

Undo NCC src steps 1-3: remove NVIDIA driver and DCGM packages of any version,
CPU/GPU attestation tools, Docker Engine, and NVIDIA Container Toolkit.
Remove their onboarding configuration, repositories, and package holds.

Options:
  --dry-run           Print cleanup commands without making changes.
  --remove-miniconda  Also delete /opt/miniconda3, including ALL its environments.
  --help              Show this help.

No interactive confirmation is requested. Use --dry-run to review first.
Stop GPU workloads and optional attestation services before running.
Docker and NVIDIA services will be stopped.
Container images, volumes, /var/lib/docker, /var/lib/containerd, model caches,
onboarding logs beside this script, kernel packages/holds from step 0, and
shared prerequisites (including build tools) are preserved. Bundled verifier
sources and copied verifier.log are kept; its script-local .venv is removed.
Miniconda is preserved unless --remove-miniconda is specified; Conda
installations elsewhere are never removed. Optional HTTP/nvattest verifier
installations are outside steps 1-3 and are not removed.

The installers did not record previous state. Matching packages are removed
even if they predated onboarding. /etc/docker/daemon.json is moved to
/etc/docker/daemon.json.bak, removing all active custom Docker settings.
Older backups are retained with numbered suffixes (.bak.~1~, .bak.~2~, ...).
Previously overwritten files cannot be restored. No blanket apt autoremove
or automatic reboot is performed.
EOF
}

# Route system mutations through this wrapper so dry runs only print commands.
run() {
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
    if [ "$DRY_RUN" -eq 0 ]; then
        "$@"
    fi
}

# Match driver/DCGM families across all versions, excluding CUDA toolkits and shared libraries.
collect_packages() {
    local inventory package status name
    inventory=$(dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n')
    PACKAGES=()
    while IFS=$'\t' read -r package status; do
        [ -n "$package" ] || continue
        # The second dpkg status character is state: skip 'n', but retain residual config ('c').
        [ "${status:1:1}" != n ] || continue
        # Match without the architecture suffix, but retain it in the apt-get argument.
        name="${package%%:*}"
        case "$name" in
            # NCC does not install NVSwitch query libraries.
            libnvidia-nscq*) continue ;;
        esac
        case "$name" in
            nvidia-driver*|nvidia-dkms*|nvidia-kernel-*|nvidia-firmware*|\
            nvidia-headless*|nvidia-compute-utils*|nvidia-utils*|nvidia-open*|nvidia-[0-9]*|\
            nvidia-modprobe|nvidia-settings|nvidia-persistenced|nvidia-prime|libnvidia-*|libxnvctrl0|\
            xserver-xorg-video-nvidia|xserver-xorg-video-nvidia-*|\
            linux-modules-nvidia-*|linux-objects-nvidia-*|linux-signatures-nvidia-*|\
            cuda-drivers|cuda-drivers-*|cuda-keyring|\
            docker-ce|docker-ce-cli|docker-ce-rootless-extras|containerd.io|\
            docker-buildx-plugin|docker-compose-plugin|\
            nvidia-container-toolkit|nvidia-container-toolkit-base|\
            datacenter-gpu-manager|datacenter-gpu-manager-*|dcgmi|libdcgm*|nv-hostengine)
                PACKAGES+=("$package")
                ;;
        esac
    done <<< "$inventory"
}

# Stop activation triggers and GPU consumers before persistenced.
stop_services() {
    local unit load_state
    for unit in \
        docker.socket docker.service containerd.service \
        nvidia-dcgm.service nvidia-cdi-refresh.path nvidia-cdi-refresh.service \
        nvidia-persistenced.service; do
        load_state=$(systemctl show --property=LoadState --value "$unit")
        # Missing units are expected after a partial installation or previous cleanup.
        [ "$load_state" != not-found ] || continue
        run systemctl stop "$unit"
        if systemctl is-enabled --quiet "$unit"; then
            run systemctl disable "$unit"
        fi
    done
}

# Step 3 overwrites the whole config; move it aside and retain older numbered backups.
clean_docker_configuration() {
    # Include dangling symlinks; moving a symlink preserves its target unchanged.
    [ -e "$DOCKER_CONFIG" ] || [ -L "$DOCKER_CONFIG" ] || return 0
    run mv --backup=numbered -- "$DOCKER_CONFIG" "${DOCKER_CONFIG}.bak"
}

# Release holds only for selected packages, leaving kernel and unrelated holds intact.
remove_packages() {
    if [ "${#PACKAGES[@]}" -eq 0 ]; then
        echo "No matching packages remain."
        return 0
    fi
    local holds held package
    local unhold=()
    holds=$(apt-mark showhold)
    while IFS= read -r held; do
        [ -n "$held" ] || continue
        for package in "${PACKAGES[@]}"; do
            if [ "${held%%:*}" = "${package%%:*}" ]; then
                unhold+=("$held")
                break
            fi
        done
    done <<< "$holds"
    if [ "${#unhold[@]}" -gt 0 ]; then
        run apt-mark unhold "${unhold[@]}"
    fi
    # Purge explicit matches only; blanket autoremove could remove shared dependencies.
    run env "${APT_ENV[@]}" apt-get "${APT_OPTS[@]}" purge -y -- "${PACKAGES[@]}"
}

uninstall_gpu_stack() {
    stop_services
    clean_docker_configuration

    # Undo step 1's root-group membership before package removal can delete the account.
    local root_group
    root_group=$(getent group root)
    if [[ ",${root_group##*:}," == *,nvidia-persistenced,* ]]; then
        run gpasswd -d nvidia-persistenced root
    fi

    # Remove onboarding pins for every driver branch before package purge regenerates initramfs.
    run rm -f -- \
        /etc/apt/preferences.d/nvidia-pin-*.pref \
        /etc/modprobe.d/nvidia-lkca.conf \
        /etc/modprobe.d/nvidia-ncc-headless.conf \
        /etc/needrestart/conf.d/99-skip-nvidia-persistenced.conf \
        /etc/systemd/system/nvidia-persistenced.service.d/override.conf \
        /etc/systemd/system/nvidia-cdi-refresh.service.d/override.conf \
        /etc/systemd/system/nvidia-dcgm.service.d/override.conf

    remove_packages

    # These repositories, keys, launchers, and generated CDI files were added outside dpkg.
    run rm -f -- \
        /etc/apt/sources.list.d/docker.list \
        /usr/share/keyrings/docker-archive-keyring.gpg \
        /etc/apt/sources.list.d/nvidia-container-toolkit.list \
        /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
        /var/run/cdi/nvidia.yaml \
        /usr/local/bin/cpu-attestation \
        /usr/local/bin/gpu-attestation
    # Keep bundled verifier sources and copied logs; remove its generated local environment only.
    run rm -rf -- \
        /usr/local/lib/azure-guest-attest \
        /usr/local/lib/local_gpu_verifier \
        "$SCRIPT_DIR/azure-guest-attest" \
        "$SCRIPT_DIR/legacy_local_gpu_verifier/.venv"
    # Step 2 may reuse a shared Miniconda installation, so deletion requires explicit opt-in.
    if [ "$REMOVE_MINICONDA" -eq 1 ]; then
        run rm -rf -- /opt/miniconda3
    fi

    run systemctl daemon-reload
    # Remove stale driver/module configuration from every existing initramfs image.
    run update-initramfs -u -k all
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Dry run complete. No changes were made."
    else
        echo "Steps 1-3 cleanup completed. Reboot before reinstalling or using the GPU."
        echo "Loaded NVIDIA modules and device state are reset by the reboot."
    fi
}

# Validate prerequisites and display the cleanup scope before changing the system.
main() {
    local argument command_name
    for argument in "$@"; do
        case "$argument" in
            --dry-run) DRY_RUN=1 ;;
            --remove-miniconda) REMOVE_MINICONDA=1 ;;
            --help|-h) usage; return 0 ;;
            *) echo "ERROR: Unknown option: $argument" >&2; usage >&2; return 1 ;;
        esac
    done
    if [ "$DRY_RUN" -eq 0 ] && [ "$EUID" -ne 0 ]; then
        echo "ERROR: Run with sudo, or use --dry-run to preview without root." >&2
        return 1
    fi
    for command_name in dpkg-query apt-mark apt-get systemctl getent gpasswd update-initramfs; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            echo "ERROR: Required command not found: $command_name" >&2
            return 1
        fi
    done
    collect_packages

    usage
    echo
    echo "Packages selected for purge (including residual package configuration):"
    if [ "${#PACKAGES[@]}" -gt 0 ]; then
        printf '  %s\n' "${PACKAGES[@]}"
    else
        echo "  None"
    fi
    if [ "$REMOVE_MINICONDA" -eq 1 ]; then
        echo "WARNING: /opt/miniconda3 and ALL environments under it will be deleted."
    fi
    uninstall_gpu_stack
}

# Allow sourcing for validation without starting destructive cleanup.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
