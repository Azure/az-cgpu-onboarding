#!/usr/bin/env bash
#
# OPTIONAL preview helper for NVIDIA's nvattest verifier:
#   1. Detect Ubuntu's version and build in the corresponding Rust container.
#   2. Export only the verifier binary.
#   3. Remove the build images.
#   4. Run GPU attestation using NVIDIA RIM and a regional OCSP service.
#
# Usage:
#   sudo bash utilities-nv-attest-verifier.sh
#   sudo bash utilities-nv-attest-verifier.sh --rebuild

set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER_FILES_DIR="$SCRIPT_DIR/nv_attest_gpu_verifier"
VERIFIER_REPO_URL="https://github.com/NVIDIA/attestation-sdk"
VERIFIER_REPO_BRANCH="release/2026.10.02"
WORK_DIR="/usr/local/lib/new_local_gpu_verifier"
OUT_BIN="$WORK_DIR/nvattest"
RP_POLICY="$VERIFIER_FILES_DIR/azure_cgpu_h100_default_policy.rego"
BUILD_LOG="$WORK_DIR/build.log"
ATTESTATION_LOG="$WORK_DIR/attestation.log"
NVAT_DOCKERFILE=""
NVIDIA_RIM_URL="https://rim.attestation.nvidia.com"
NVIDIA_OCSP_URL="https://ocsp.ndis.nvidia.com"
if [ -z "${NVAT_BUILD_JOBS:-}" ]; then
    NVAT_BUILD_JOBS=$(( $(nproc) - 1 ))
    if [ "$NVAT_BUILD_JOBS" -lt 1 ]; then
        NVAT_BUILD_JOBS=1
    fi
fi
REBUILD=0

# Parse parameters.
NVAT_BUILD_IMAGE=""
case "${1:-}" in
    "") ;;
    --rebuild) REBUILD=1 ;;
    *)
        echo "Usage: sudo bash utilities-nv-attest-verifier.sh [--rebuild]" >&2
        exit 1
        ;;
esac
if [ "$#" -gt 1 ]; then
    echo "Usage: sudo bash utilities-nv-attest-verifier.sh [--rebuild]" >&2
    exit 1
fi

detect_ubuntu_version() {
    (
        . /etc/os-release
        if [ "${ID:-}" = ubuntu ]; then printf '%s\n' "$VERSION_ID"; fi
    )
}

configure_build_image() {
    NVAT_TARGET_UBUNTU="$(detect_ubuntu_version)"
    case "$NVAT_TARGET_UBUNTU" in
        22.04)
            NVAT_DOCKERFILE="$VERIFIER_FILES_DIR/Dockerfile.bullseye"
            ;;
        24.04)
            NVAT_DOCKERFILE="$VERIFIER_FILES_DIR/Dockerfile.azlinux3"
            ;;
        *) echo "ERROR: Builds support Ubuntu 22.04 or 24.04 only." >&2; return 1 ;;
    esac
    if [ ! -f "$NVAT_DOCKERFILE" ]; then
        echo "ERROR: Required Dockerfile not found: $NVAT_DOCKERFILE" >&2
        return 1
    fi
    # The selected Dockerfile is the single source of truth for its base image.
    NVAT_BUILD_IMAGE="$(awk 'toupper($1) == "FROM" { sub(/\r$/, "", $2); print $2; exit }' "$NVAT_DOCKERFILE")" || return 1
    if ! [[ "$NVAT_BUILD_IMAGE" =~ ^mcr\.microsoft\.com/[^[:space:]\$]+@sha256:[[:xdigit:]]{64}$ ]]; then
        echo "ERROR: Dockerfile must specify a literal, digest-pinned MCR base image: $NVAT_DOCKERFILE" >&2
        return 1
    fi
}

thim_base_for_region() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        eastus2)       echo "https://useast2.thim.azure.net" ;;
        centraluseuap) echo "https://uscentraleuap.thim.azure.net" ;;
        westeurope)    echo "https://europewest.thim.azure.net" ;;
        centralus)     echo "https://uscentral.thim.azure.net" ;;
        *)             echo "" ;;
    esac
}

detect_azure_region() {
    curl -s -H "Metadata: true" --max-time 5 \
        "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null \
        | grep -o '"location":"[^"]*"' | head -1 | cut -d'"' -f4
}

build_verifier() {
    echo "============================================================"
    echo "  Cloning and building nvattest in a Rust container"
    echo "============================================================"

    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: Docker is required. Run step-3-install-gpu-tools.sh first." >&2
        return 1
    fi
    if ! [[ "$NVAT_BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: NVAT_BUILD_JOBS must be a positive integer." >&2
        return 1
    fi
    configure_build_image || return 1
    echo "This could take up to 5 minutes"
    sudo mkdir -p "$WORK_DIR"
    sudo rm -f "$OUT_BIN"
    echo "Detected Ubuntu $NVAT_TARGET_UBUNTU; using its configured Rust build image."
    echo "Pulling build image: $NVAT_BUILD_IMAGE"
    sudo docker pull --quiet "$NVAT_BUILD_IMAGE" >/dev/null || return 1

    local build_context build_image build_container
    local build_rc=0 export_rc=0 image_cleanup_rc=0
    build_context="$(mktemp -d /tmp/nvattest-context_XXXXXX)"
    build_image="nvattest-builder:$$"
    build_container="nvattest-export-$$"
    cp "$NVAT_DOCKERFILE" "$build_context/Dockerfile"

    sudo docker build --no-cache --force-rm \
        --build-arg VERIFIER_REPO_URL="$VERIFIER_REPO_URL" \
        --build-arg VERIFIER_REPO_BRANCH="$VERIFIER_REPO_BRANCH" \
        --build-arg NVAT_BUILD_JOBS="$NVAT_BUILD_JOBS" \
        --tag "$build_image" "$build_context" >"$BUILD_LOG" 2>&1 || build_rc=$?

    if [ "$build_rc" -eq 0 ]; then
        sudo docker create --name "$build_container" "$build_image" /bin/true >/dev/null || export_rc=$?
        if [ "$export_rc" -eq 0 ]; then
            sudo docker cp "$build_container:/nvattest" "$OUT_BIN" || export_rc=$?
            sudo chmod 0755 "$OUT_BIN"
        fi
    fi

    echo "Removing temporary build resources..."
    sudo docker rm -f "$build_container" >/dev/null 2>&1 || true
    sudo docker image rm "$build_image" >/dev/null 2>&1 || true
    sudo docker image rm "$NVAT_BUILD_IMAGE" >/dev/null || image_cleanup_rc=$?
    rm -rf "$build_context"

    if [ "$build_rc" -ne 0 ]; then
        echo "ERROR: nvattest build failed. Details: $BUILD_LOG" >&2
        tail -50 "$BUILD_LOG" >&2
        return 1
    fi
    if [ "$export_rc" -ne 0 ]; then
        echo "ERROR: Failed to export nvattest build artifacts." >&2
        return 1
    fi
    if [ "$image_cleanup_rc" -ne 0 ]; then
        echo "ERROR: Failed to remove the selected Rust build image." >&2
        return 1
    fi
    if [ ! -x "$OUT_BIN" ]; then
        echo "ERROR: Build completed without producing $OUT_BIN." >&2
        return 1
    fi

    echo "nvattest built successfully."
}

run_gpu_attestation() {
    local region thim_base ocsp_url rc
    local policy_args=()

    region="$(detect_azure_region)"
    thim_base="$(thim_base_for_region "$region")"
    if [ -z "$thim_base" ]; then
        ocsp_url="$NVIDIA_OCSP_URL"
        echo "Using NVIDIA OCSP for region '${region:-unknown}'."
    else
        ocsp_url="${thim_base}/nvidia/ocsp/"
        policy_args=(--relying-party-policy "$RP_POLICY")
    fi

    echo "============================================================"
    echo "  GPU Attestation"
    echo "============================================================"
    echo "RIM: NVIDIA"
    echo "OCSP: $ocsp_url"

    sudo "$OUT_BIN" attest --device gpu --verifier local \
        --rim-url "$NVIDIA_RIM_URL" --ocsp-url "$ocsp_url" \
        --ocsp-cert-id-hash sha-384 \
        "${policy_args[@]}" \
        >"$ATTESTATION_LOG" 2>&1
    rc=$?

    if [ "$rc" -ne 0 ] && [ -n "$thim_base" ]; then
        echo "THIM OCSP attestation failed; retrying with NVIDIA OCSP." >&2
        {
            echo
            echo "THIM OCSP attestation failed; retrying with NVIDIA OCSP."
        } >>"$ATTESTATION_LOG"
        sudo "$OUT_BIN" attest --device gpu --verifier local \
            --rim-url "$NVIDIA_RIM_URL" --ocsp-url "$NVIDIA_OCSP_URL" \
            --ocsp-cert-id-hash sha-384 \
            >>"$ATTESTATION_LOG" 2>&1
        rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        sed '/^[[:space:]]*GPU attestation was successful[.!]*[[:space:]]*$/Id' \
            "$ATTESTATION_LOG"
        echo "GPU Attestation is Successful."
    else
        echo "GPU Attestation failed. Details: $ATTESTATION_LOG" >&2
    fi
    return "$rc"
}

main() {
    if [ ! -f "$RP_POLICY" ]; then
        echo "ERROR: Required relying-party policy not found: $RP_POLICY" >&2
        return 1
    fi

    if [ "$REBUILD" = "1" ] || [ ! -x "$OUT_BIN" ]; then
        if [ "$REBUILD" = "1" ]; then
            echo "A fresh nvattest build was requested."
        else
            echo "nvattest is not installed; building it now."
        fi
        build_verifier || return 1
    else
        echo "Reusing the existing nvattest binary at $OUT_BIN."
    fi
    if ! "$OUT_BIN" attest --help | grep -F -- '--ocsp-cert-id-hash' >/dev/null; then
        echo "ERROR: Installed nvattest lacks native OCSP hash selection. Run this utility with --rebuild to update it." >&2
        return 1
    fi
    run_gpu_attestation
}

main
