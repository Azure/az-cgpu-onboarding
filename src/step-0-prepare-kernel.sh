## This module helps prepare kernel for nvidia driver installation.
##
## Example:
##      sudo bash step-0-prepare-kernel.sh [--enable-proposed]
##

ENABLE_UBUNTU_PROPOSED_SOURCE_LIST=0
ENABLE_UBUNTU_SNAPSHOT_SERVICE=0
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

# Enable Ubuntu proposed source list if ENABLE_UBUNTU_PROPOSED_SOURCE_LIST is set to 1
if [ "$ENABLE_UBUNTU_PROPOSED_SOURCE_LIST" = "1" ]; then
    sudo sh -c "echo 'deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -cs)-proposed restricted main multiverse universe' > /etc/apt/sources.list.d/ubuntu-$(lsb_release -cs)-proposed.list"
fi

# Enable Ubuntu snapshot service if ENABLE_UBUNTU_SNAPSHOT_SERVICE is set to 1
if [ "$ENABLE_UBUNTU_SNAPSHOT_SERVICE" = "1" ]; then
    enable_ubuntu_snapshot_service
fi

# Due to inconsistency upgrade from VM just booting up, adding 5 second delay. 
sleep 5
sudo apt update
sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
echo Y | sudo apt upgrade

echo "Rebooting system to apply kernel updates..."
sudo reboot
