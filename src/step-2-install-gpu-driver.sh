## This module helps install gpu driver to current gpu driver version APM_470.10.07_5.11.0-1028.31.tar.
##
## Requirements: 
##		nvdia driver:		APM_470.10.10_5.11.0-1028.31.tar
## 		kenrel version:		5.11.0-1028-azure
##
## Example:
##		bash step-2-install-gpu-driver.sh
##


REQUIRED_KERNEL_VERSION="5.11.0-1028-azure"
DRIVER_PACKAGE=APM_470.10.10_5.11.0-1028.31.tar


## Install gpu driver required dependency and driver itself. It will reboot the system at the end.
install_gpu_driver(){
    current_kernel=$(uname -r)
    if [ "$current_kernel" != "$REQUIRED_KERNEL_VERSION" ]; 
    then
    	echo "Current kernel version: ($current_kernel), expected: ($REQUIRED_KERNEL_VERSION)."
    	echo "Please retry step-1-install-kernel."
    else 
    	echo "kernel verified successfully, start driver installation."
	    sudo apt-get install -y libgl1 binutils xserver-xorg-core

	    sudo systemctl set-default multi-user.target
	    mkdir apm470driver
	    tar -xvf $DRIVER_PACKAGE --directory apm470driver
	    sudo dpkg -i apm470driver/*.deb
	    sudo reboot
	fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    install_gpu_driver "$@"
fi