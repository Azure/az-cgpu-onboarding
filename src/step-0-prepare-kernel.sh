## This module helps prepare kernel for nvidia driver installation.
##
## Example: 
##      bash step-0-prepare-kernel.sh 
##

sudo apt update; 
sudo apt-mark hold linux-azure-6.2 linux-image-6.2.0 linux-azure linux-headers-azure linux-image-azure linux-tools-azure linux-cloud-tools-azure;
sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
echo Y | sudo apt upgrade;

sudo cp nvidia-lkca.conf /etc/modprobe.d/nvidia-lkca.conf; echo Y | sudo update-initramfs -u

sudo reboot
