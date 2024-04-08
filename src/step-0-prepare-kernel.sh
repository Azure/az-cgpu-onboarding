## This module helps prepare kernel for nvidia driver installation.
##
## Example:
##      sudo bash step-0-prepare-kernel.sh
##

sudo apt update
sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
nvidia_supported_kernel_version=$(
    apt-cache search linux-modules-nvidia-550-server-open-azure |
        grep -oP 'linux-modules-nvidia-550-server-open-\K[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-azure'
)
sudo bash ./utilities-update-kernel.sh -k "$nvidia_supported_kernel_version"
