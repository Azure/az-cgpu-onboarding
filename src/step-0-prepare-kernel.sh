## This module helps prepare kernel for nvidia driver installation.
##
## Example:
##      sudo bash step-0-prepare-kernel.sh [--enable-proposed] [--enable-snapshot <timestamp>]
##

ENABLE_UBUNTU_PROPOSED_SOURCE_LIST=0
ENABLE_UBUNTU_PROPOSED2_KERNEL_PPA=0
ENABLE_UBUNTU_SNAPSHOT_SERVICE=0
DISABLE_UBUNTU_UNATTENDED_UPGRADES=1
TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE=20250818T120000Z
OPTION_ALREADY_SET=0

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

enable_ubuntu_snapshot_service() {
    echo "Enabling Ubuntu snapshot service with timestamp: $TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE"
    
    # Ubuntu 22.04 needs to enable snapshot in sources.list
    ubuntu_version=$(lsb_release -rs)
    if dpkg --compare-versions "$ubuntu_version" "eq" "22.04"; then
        local sources_list="/etc/apt/sources.list"
        sudo cp "$sources_list" "$sources_list.backup"
        sudo sed -i "/^deb /s/deb /deb [snapshot=yes] /" "$sources_list"
    fi  

    echo "APT::Snapshot \"$TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE\";" | sudo tee /etc/apt/apt.conf.d/50snapshot
    sudo apt-get -o DPkg::Lock::Timeout=300 update
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

# Add delay due to inconsistency upgrade from VM just booting up
sleep 10

# Disable Ubuntu unattended upgrades
if [ "$DISABLE_UBUNTU_UNATTENDED_UPGRADES" = "1" ]; then
    sudo systemctl stop unattended-upgrades
    sudo apt-get -o DPkg::Lock::Timeout=300 purge -y unattended-upgrades
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

sudo apt-get -o DPkg::Lock::Timeout=300 update
sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
sudo apt-get -o DPkg::Lock::Timeout=300 -o APT::Get::Always-Include-Phased-Updates=true -o Debug::pkgProblemResolver=true dist-upgrade -y

echo "Rebooting system to apply kernel updates..."
sudo reboot
