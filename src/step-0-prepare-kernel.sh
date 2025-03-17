## This module helps prepare kernel for nvidia driver installation.
##
## Example:
##      sudo bash step-0-prepare-kernel.sh [--enable-proposed]
##

ENABLE_UBUNTU_PROPOSED_SOURCE_LIST=0
ENABLE_UBUNTU_SNAPSHOT_SERVICE=0
DISABLE_UBUNTU_UNATTENDED_UPGRADES=1
TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE=20240405T120000Z

# Parse command-line arguments
if [ $# -ne 0 ]; then
    if [ "$1" = "--enable-proposed" ]; then
        ENABLE_UBUNTU_PROPOSED_SOURCE_LIST=1
    else
        echo "Invalid argument: $1"
        echo "Usage: $0 [--enable-proposed]"
        exit 1
    fi
fi

enable_ubuntu_snapshot_service() {
    local sources_list="/etc/apt/sources.list"
    sudo cp "$sources_list" "$sources_list.backup"
    sudo sed -i "/^deb /s/deb /deb [snapshot=$TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE] /" "$sources_list"
}

enable_ubuntu_proposed_pocket() {
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

# Enable Ubuntu proposed source list if ENABLE_UBUNTU_PROPOSED_SOURCE_LIST is set to 1
if [ "$ENABLE_UBUNTU_PROPOSED_SOURCE_LIST" = "1" ]; then
    enable_ubuntu_proposed_pocket
fi

# Enable Ubuntu snapshot service if ENABLE_UBUNTU_SNAPSHOT_SERVICE is set to 1
if [ "$ENABLE_UBUNTU_SNAPSHOT_SERVICE" = "1" ]; then
    enable_ubuntu_snapshot_service
fi

# Disable Ubuntu unattended upgrades
if [ "$DISABLE_UBUNTU_UNATTENDED_UPGRADES" = "1" ]; then
    sudo systemctl stop unattended-upgrades
    sudo apt-get -o DPkg::Lock::Timeout=300 purge -y unattended-upgrades
fi

# Due to inconsistency upgrade from VM just booting up, adding 5 second delay.
sleep 5
sudo apt -o DPkg::Lock::Timeout=300 update
sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
echo Y | sudo apt -o DPkg::Lock::Timeout=300 upgrade

echo "Rebooting system to apply kernel updates..."
sudo reboot
