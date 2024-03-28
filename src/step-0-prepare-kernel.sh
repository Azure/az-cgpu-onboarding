## This module helps prepare kernel for nvidia driver installation.
##
## Example:
##      bash step-0-prepare-kernel.sh
##

sudo add-apt-repository --yes ppa:canonical-kernel-team/proposed2 # add security Proposed PPA for kernel
sudo apt update
sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
echo Y | sudo apt upgrade

echo "Rebooting system to apply kernel updates..."
sudo reboot
