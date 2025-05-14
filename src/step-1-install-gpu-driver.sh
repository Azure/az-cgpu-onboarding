## This module helps install gpu driver to the lastest r570 Nvidia driver version.
##
## Requirements:
##      Minimum Nvidia driver:       v570.86.15
##      Minimum kernel version:      6.8.0-1025-azure
##
## Example:
##      sudo bash step-1-install-gpu-driver.sh
##

MINIMUM_KERNEL_VERSION="6.8.0-1025-azure"

## Install gpu driver required dependency and driver itself. It will reboot the system at the end.
install_gpu_driver() {
    current_kernel=$(uname -r)
    echo -e "$MINIMUM_KERNEL_VERSION\n$current_kernel" | sort --check=quiet --version-sort
    if [ "$?" -ne "0" ]; then
        echo "Current kernel version: ($current_kernel), expected: (>= $MINIMUM_KERNEL_VERSION)."
    else
        echo "Current kernel version: $current_kernel"

        # install neccessary kernel update.
        sudo apt-get update
        sudo apt-get -y install initramfs-tools

        # Apply change to modprobe.d and run update-initramfs
        sudo cp nvidia-lkca.conf /etc/modprobe.d/nvidia-lkca.conf
        sudo update-initramfs -u -k $current_kernel

        # verify secure boot
        secure_boot_status=$(mokutil --sb)
        echo "SecureBoot Status: $secure_boot_status"

        echo "kernel verified successfully, start driver installation."
        echo "start gpu driver log."

        # Install r570 nvidia driver
        sudo apt -o DPkg::Lock::Timeout=300 install -y gcc g++ make
        sudo apt -o DPkg::Lock::Timeout=300 install -y nvidia-driver-570-server-open linux-modules-nvidia-570-server-open-azure

        # Enable persistence mode and set GPU ready state on boot
        sudo nvidia-smi -pm 1
        echo "add nvidia persitenced on reboot."
        sudo bash -c 'echo "#!/bin/bash" > /etc/rc.local; echo "nvidia-smi -pm 1" >>/etc/rc.local; echo "nvidia-smi conf-compute -srs 1" >> /etc/rc.local;'
        sudo chmod +x /etc/rc.local
        echo "not reboot"

    fi
}

# Due to inconsistency upgrade from VM just booting up, adding 5 second delay.
sleep 5

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    install_gpu_driver "$@" 2>&1 | tee logs/current-operation.log | tee -a logs/all-operation.log
fi
