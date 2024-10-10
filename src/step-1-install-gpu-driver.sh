## This module helps install gpu driver to the lastest r550 Nvidia driver version.
##
## Requirements:
##      Minimum Nvidia driver:       v550.90.07
##      Minimum kernel version:      6.5.0-1024-azure
##
## Example:
##      sudo bash step-1-install-gpu-driver.sh
##

MINIMUM_KERNEL_VERSION="6.5.0-1024-azure"
MAX_RETRY=3

## Install gpu driver required dependency and driver itself. It will reboot the system at the end.
install_gpu_driver() {
    current_kernel=$(uname -r)
    echo -e "$MINIMUM_KERNEL_VERSION\n$current_kernel" | sort --check=quiet --version-sort
    if [ "$?" -ne "0" ]; then
        echo "Current kernel version: ($current_kernel), expected: (>= $MINIMUM_KERNEL_VERSION)."
        # echo "Please try utilities-update-kernel.sh 6.5.0-1024-azure."
    else
        echo "Current kernel version: $current_kernel"

        # Apply change to modprobe.d and run update-initramfs
        sudo cp nvidia-lkca.conf /etc/modprobe.d/nvidia-lkca.conf
        sudo update-initramfs -u -k $current_kernel

        # verify secure boot and key enrollment.
        secure_boot_status=$(mokutil --sb)
        nvidia_signing_key=$(mokutil --list-enrolled | grep "NVIDIA")
        #if [ "$secure_boot_status" == "SecureBoot enabled" ] && [ "$nvidia_signing_key" == "" ];
        #then
        #    echo "Please enroll nvidia signing key for secure-boot-enabled VM before install GPU driver."
        #    return 0
        #fi

        # install neccessary kernel update.
        sudo apt-get update
        sudo apt-get -y install

        echo "kernel verified successfully, start driver installation."
        echo "start gpu driver log."

        # Install r550 nvidia driver
        sudo apt install -y gcc g++ make
        sudo apt install -y nvidia-driver-550-server-open linux-modules-nvidia-550-server-open-$current_kernel

        # capture transient couldn't get lock issue and retry the operation with maximum retry count of 3.
        lockError=$(cat logs/current-operation.log | grep "Could not get lock")
        if [ "$lockError" != "" ] && [ $MAX_RETRY \> 0 ]; then
            # start of retry, clean up current-operation log.
            MAX_RETRY=$((MAX_RETRY - 1)) >logs/current-operation.log
            echo "Found lock error retry install gpu driver operations."
            echo "Retry left:"
            echo $MAX_RETRY
            sudo apt-get install -y libgl1 binutils xserver-xorg-core
            sudo apt --fix-broken install
            install_gpu_driver "$@"
        else
            if [ "$lockError" == "" ]; then
                sudo nvidia-smi -pm 1
                echo "add nvidia persitenced on reboot."
                sudo bash -c 'echo "#!/bin/bash" > /etc/rc.local; echo "nvidia-smi -pm 1" >>/etc/rc.local; echo "nvidia-smi conf-compute -srs 1" >> /etc/rc.local;'
                sudo chmod +x /etc/rc.local
                echo "not reboot"
            else
                echo "Couldn't resolve lock issue with 3 time retries. Please restart the VM and try it again."
            fi
        fi
    fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    install_gpu_driver "$@" 2>&1 | tee logs/current-operation.log | tee -a logs/all-operation.log
fi
