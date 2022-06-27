## This module helps install gpu driver to current gpu driver version APM_470.10.07_5.11.0-1028.31.tar.
##
## Requirements: 
##      nvdia driver:       APM_470.10.10_5.11.0-1028.31.tar
##      kenrel version:     5.11.0-1028-azure
##
## Example:
##      bash step-1-install-gpu-driver.sh
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
        echo "Please try utilities-update-kernel.sh 5.11.0-1028-azure."
    else 
        # lock the current kernel version from update.
        sudo cp nvidia.pref /etc/apt/preferences.d/nvidia.pref
        sudo chmod 0644 /etc/apt/preferences.d/nvidia.pref
        sudo cat /etc/apt/preferences.d/nvidia.pref

        # verify secure boot and key enrollment.        
        secure_boot_status=$(mokutil --sb)
        nvidia_signing_key=$(mokutil --list-enrolled | grep "NVIDIA")
        if [ "$secure_boot_status" == "SecureBoot enabled" ] && [ "$nvidia_signing_key" == "" ];
        then 
            echo "Please enroll nvidia signing key for secure-boot-enabled VM before install GPU driver."
            return 0
        fi

        # install neccessary kernel update.
        sudo apt-get update   
        sudo apt-get -y install   

        echo "kernel verified successfully, start driver installation." 
        echo "start gpu driver log."   

        sudo apt-get install -y libgl1 binutils xserver-xorg-core   

        sudo systemctl set-default multi-user.target   
        mkdir apm470driver
        tar -xvf $DRIVER_PACKAGE --directory apm470driver 
        sudo dpkg -i apm470driver/*.deb   

        # capture transient couldn't get lock issue and retry the operation with maximum retry count of 3.
        lockError=$(cat logs/current-operation.log | grep "Could not get lock")
        if [ "$lockError" != "" ] && [ $MAX_RETRY \> 0 ];
        then
            # start of retry, clean up current-operation log.
            MAX_RETRY=$((MAX_RETRY-1)) > logs/current-operation.log 
            echo "Found lock error retry install gpu driver operations."  
            echo "Retry left:"   
            echo $MAX_RETRY   
            sudo apt-get install -y libgl1 binutils xserver-xorg-core   
            sudo apt --fix-broken install   
            install_gpu_driver "$@" 
        else 
            if [ "$lockError" == "" ];
            then
                sudo reboot
            else 
                echo "Couldn't resolve lock issue with 3 time retries. Please restart the VM and try it again."
            fi 
        fi
    fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    mkdir logs
    install_gpu_driver "$@" 2>&1 | tee logs/current-operation.log | tee -a logs/all-operation.log
fi