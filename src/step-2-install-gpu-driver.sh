## This module helps install gpu driver to current gpu driver version APM_470.10.07_5.11.0-1028.31.tar.
##
## Requirements: 
##      nvdia driver:       APM_470.10.10_5.11.0-1028.31.tar
##      kenrel version:     5.11.0-1028-azure
##
## Example:
##      bash step-2-install-gpu-driver.sh
##


REQUIRED_KERNEL_VERSION="5.11.0-1028-azure"
DRIVER_PACKAGE=APM_470.10.10_5.11.0-1028.31.tar
MAX_RETRY=3


## Install gpu driver required dependency and driver itself. It will reboot the system at the end.
install_gpu_driver(){
    current_kernel=$(uname -r)
    if [ "$current_kernel" != "$REQUIRED_KERNEL_VERSION" ]; 
    then
        echo "Current kernel version: ($current_kernel), expected: ($REQUIRED_KERNEL_VERSION)."
        echo "Please retry step-1-install-kernel."
    else 
        echo "kernel verified successfully, start driver installation." > step-2-out.log
        sudo apt-get install -y libgl1 binutils xserver-xorg-core &>> step-2-out.log

        sudo systemctl set-default multi-user.target &>> step-2-out.log
        mkdir apm470driver
        tar -xvf $DRIVER_PACKAGE --directory apm470driver 
        sudo dpkg -i apm470driver/*.deb &>> step-2-out.log
        lockError=$(cat step-2-out.log | grep "Could not get lock")
        if [ "$lockError" != "" ];
        then
            MAX_RETRY=$((MAX_RETRY-1))

            if [ $MAX_RETRY \> 0 ];
            then
                echo "Found lock error retry install gpu driver operations."
                echo "Retry left:"
                echo $MAX_RETRY
                sudo apt-get install -y libgl1 binutils xserver-xorg-core
                sudo apt --fix-broken install
                install_gpu_driver "$@"
            else
                echo "After 3 times retry could not resolve lock issue. Please try to kill below process info:"
                echo lockError
            fi

        else 
            sudo reboot
        fi
    fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    install_gpu_driver "$@"
fi