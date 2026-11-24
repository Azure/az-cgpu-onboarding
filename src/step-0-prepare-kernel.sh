## This module helps prepare kernel for nvidia driver installation.
##
## Example:
##      sudo bash step-0-prepare-kernel.sh [--enable-proposed] [--enable-snapshot <timestamp>] [--no-reboot]
##
## Omitting --enable-snapshot removes any snapshot configured by a previous run.
## Supplying a timestamp replaces the previous snapshot selection.
## --no-reboot lets an orchestrator check the result before requesting a reboot.
##

set -euo pipefail

ENABLE_UBUNTU_PROPOSED_SOURCE_LIST=0
ENABLE_UBUNTU_PROPOSED2_KERNEL_PPA=0
ENABLE_UBUNTU_SNAPSHOT_SERVICE=0
DISABLE_UBUNTU_UNATTENDED_UPGRADES=1
TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE=20260315T120000Z
OPTION_ALREADY_SET=0
REBOOT_AFTER_PREPARATION=1

# Common apt-get options: lock timeout, retry limit, and network timeouts
APT_OPTS="-o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --enable-proposed)
            ENABLE_UBUNTU_PROPOSED_SOURCE_LIST=1
            shift
            ;;
        --enable-proposed2)
            ENABLE_UBUNTU_PROPOSED2_KERNEL_PPA=1
            shift
            ;;
        --enable-snapshot)
            if [[ -n "${2:-}" && "$2" != --* ]]; then
                TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE="$2"
                ENABLE_UBUNTU_SNAPSHOT_SERVICE=1
                shift 2
            else
                echo "Error: --enable-snapshot requires a timestamp value."
                echo "Usage: $0 [--enable-proposed] [--enable-snapshot <timestamp>] [--no-reboot]"
                exit 1
            fi
            ;;
        --no-reboot)
            REBOOT_AFTER_PREPARATION=0
            shift
            ;;
        *)
            echo "Invalid argument: $1"
            echo "Usage: $0 [--enable-proposed] [--enable-snapshot <timestamp>] [--no-reboot]"
            exit 1
            ;;
    esac
done

# Throws an error if more than one feature is enabled
enabled_count=$((ENABLE_UBUNTU_PROPOSED_SOURCE_LIST + ENABLE_UBUNTU_SNAPSHOT_SERVICE + ENABLE_UBUNTU_PROPOSED2_KERNEL_PPA))
if [ "$enabled_count" -gt 1 ]; then
    echo "Error: You can only enable one feature at a time: --enable-proposed, --enable-snapshot, or --enable-proposed2."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

enable_ubuntu_proposed_pocket() {
    echo "Enabling Ubuntu proposed pocket"
    sudo sh -c "echo 'deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -cs)-proposed restricted main multiverse universe' > /etc/apt/sources.list.d/ubuntu-$(lsb_release -cs)-proposed.list"

    # Set APT pinning for Ubuntu 24.04 to prioritize proposed packages
    if [ "$(lsb_release -rs)" = "24.04" ]; then
        echo "Setting APT pinning for Ubuntu 24.04 to prioritize proposed packages..."
        sudo tee /etc/apt/preferences.d/proposed-priority <<EOF
Package: *
Pin: release a=noble-proposed
Pin-Priority: 1001
EOF
    fi
}

prepare_kernel() {
    local waited=0
    while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if [ "$waited" -ge 600 ]; then
            echo "ERROR: APT package-list lock is still held after $waited seconds."
            return 1
        fi
        echo "Waiting for APT package-list lock to be released..."
        sleep 5
        waited=$((waited + 5))
    done

    # The periodic list refresh is configured independently of unattended-upgrades.
    if [ "$DISABLE_UBUNTU_UNATTENDED_UPGRADES" = "1" ]; then
        printf 'APT::Periodic::Update-Package-Lists "0";\n' \
            | sudo tee /etc/apt/apt.conf.d/99-cgpu-disable-list-refresh >/dev/null
        sudo systemctl stop unattended-upgrades || true
        sudo apt-get $APT_OPTS purge -y unattended-upgrades
        sleep 10
    fi

    # Enable Ubuntu proposed source list if ENABLE_UBUNTU_PROPOSED_SOURCE_LIST is set to 1
    if [ "$ENABLE_UBUNTU_PROPOSED_SOURCE_LIST" = "1" ]; then
        enable_ubuntu_proposed_pocket
        sleep 10
    fi

    # Enable Ubuntu Proposed 2 kernel PPA if ENABLE_UBUNTU_PROPOSED2_KERNEL_PPA is set to 1
    if [ "$ENABLE_UBUNTU_PROPOSED2_KERNEL_PPA" = "1" ]; then
        echo "Enabling Ubuntu Proposed 2 kernel PPA"
        sudo add-apt-repository --no-update -y ppa:canonical-kernel-team/proposed2
        sleep 10
    fi

    # Apply snapshot
    if [ "$ENABLE_UBUNTU_SNAPSHOT_SERVICE" = "1" ]; then
        sudo bash "$SCRIPT_DIR/utilities-enable-snapshot.sh" "$TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE" --no-update || return 1
        sleep 10
    else
        sudo bash "$SCRIPT_DIR/utilities-enable-snapshot.sh" --disable || return 1
    fi

    # DPkg::Lock::Timeout does not cover the package-list lock.
    while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        echo "Waiting for APT package-list lock to be released..."
        sleep 5
    done
    sudo apt-get $APT_OPTS -o APT::Update::Error-Mode=any update
    sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
    sudo apt-get $APT_OPTS \
        -o APT::Get::Always-Include-Phased-Updates=true \
        -o Debug::pkgProblemResolver=true \
        dist-upgrade -y --allow-downgrades

    echo "Kernel updates applied."
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    echo -e "\n===== [step-0-prepare-kernel.sh] $(date) =====" | tee logs/current-operation.log | tee -a logs/all-operation.log
    prepare_kernel "$@" 2>&1 | tee -a logs/current-operation.log | tee -a logs/all-operation.log
    if [ "$REBOOT_AFTER_PREPARATION" = "1" ]; then
        echo "System will reboot."
        sudo reboot
    fi
fi
