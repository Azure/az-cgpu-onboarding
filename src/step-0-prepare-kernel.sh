## This module helps prepare kernel for nvidia driver installation.
##
## Example:
##      sudo bash step-0-prepare-kernel.sh [--enable-proposed] [--enable-snapshot <timestamp>]
##

ENABLE_UBUNTU_PROPOSED_SOURCE_LIST=0
ENABLE_UBUNTU_PROPOSED2_KERNEL_PPA=0
ENABLE_UBUNTU_SNAPSHOT_SERVICE=0
DISABLE_UBUNTU_UNATTENDED_UPGRADES=1
TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE=20260315T120000Z
OPTION_ALREADY_SET=0

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
            if [[ -n "$2" && "$2" != --* ]]; then
                TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE="$2"
                ENABLE_UBUNTU_SNAPSHOT_SERVICE=1
                shift 2
            else
                echo "Error: --enable-snapshot requires a timestamp value."
                echo "Usage: $0 [--enable-proposed] [--enable-snapshot <timestamp>]"
                exit 1
            fi
            ;;
        *)
            echo "Invalid argument: $1"
            echo "Usage: $0 [--enable-proposed] [--enable-snapshot <timestamp>]"
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

enable_ubuntu_snapshot_service() {
    sudo bash "$SCRIPT_DIR/utilities-enable-snapshot.sh" "$TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE"
}

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
    # Add delay due to inconsistency upgrade from VM just booting up
    sleep 10

    # Disable Ubuntu unattended upgrades
    if [ "$DISABLE_UBUNTU_UNATTENDED_UPGRADES" = "1" ]; then
        sudo systemctl stop unattended-upgrades
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
        sudo add-apt-repository -y ppa:canonical-kernel-team/proposed2
        sleep 10
    fi

    # Enable Ubuntu snapshot service if ENABLE_UBUNTU_SNAPSHOT_SERVICE is set to 1
    if [ "$ENABLE_UBUNTU_SNAPSHOT_SERVICE" = "1" ]; then
        enable_ubuntu_snapshot_service
        sleep 10
    fi

    sudo apt-get $APT_OPTS update
    sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
    sudo apt-get $APT_OPTS \
        -o APT::Get::Always-Include-Phased-Updates=true \
        -o Debug::pkgProblemResolver=true \
        dist-upgrade -y --allow-downgrades

    echo "Kernel updates applied. System will reboot."
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    echo -e "\n===== [step-0-prepare-kernel.sh] $(date) =====" | tee logs/current-operation.log | tee -a logs/all-operation.log
    prepare_kernel "$@" 2>&1 | tee -a logs/current-operation.log | tee -a logs/all-operation.log
    sudo reboot
fi
