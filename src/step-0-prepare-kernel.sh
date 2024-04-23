## This module helps prepare kernel for nvidia driver installation.
##
## Example:
##      sudo bash step-0-prepare-kernel.sh
##

ENABLE_UBUNTU_SNAPSHOT_SERVICE=0
TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE=20240405T120000Z

enable_ubuntu_snapshot_service() {
    local sources_list="/etc/apt/sources.list"
    sudo cp "$sources_list" "$sources_list.backup"
    sudo sed -i "/^deb /s/deb /deb [snapshot=$TIMESTAMP_UBUNTU_SNAPSHOT_SERVICE] /" "$sources_list"
}

# Enable Ubuntu snapshot service if ENABLE_UBUNTU_SNAPSHOT_SERVICE is set to 1
if [ "$ENABLE_UBUNTU_SNAPSHOT_SERVICE" == "1" ]; then
    enable_ubuntu_snapshot_service
fi

sudo apt update
sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
echo Y | sudo apt upgrade

echo "Rebooting system to apply kernel updates..."
sudo reboot
