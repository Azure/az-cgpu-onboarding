## This module helps prepare kernel for nvidia driver installation.
##
## Example: 
##      bash step-0-prepare-kernel.sh 
##

sudo apt update; echo Y | sudo apt upgrade;

sudo cp nvidia-lkca.conf /etc/modprobe.d/nvidia-lkca.conf; echo Y | sudo update-initramfs -u

sudo reboot
