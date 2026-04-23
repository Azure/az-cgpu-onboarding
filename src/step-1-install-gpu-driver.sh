#!/usr/bin/env bash

## This module helps install gpu driver to the lastest r590 Nvidia driver version.
##
## Requirements:
##      Minimum Nvidia driver:       v570.86.15
##      Minimum kernel version:      6.8.0-1025-azure
##
## Example:
##      sudo bash step-1-install-gpu-driver.sh
##

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MINIMUM_KERNEL_VERSION="6.8.0-1025-azure"

# Common apt-get options: lock timeout, retry limit, and network timeouts
APT_OPTS="-o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"

# Install gpu driver required dependency and driver itself.
install_gpu_driver() {
    # Verify current kernel version meets minimum requirement
    local current_kernel
    current_kernel=$(uname -r)
    echo "Current kernel version: $current_kernel"
    echo -e "$MINIMUM_KERNEL_VERSION\n$current_kernel" | sort --check=quiet --version-sort
    if [ "$?" -ne "0" ]; then
        echo "ERROR: Current kernel version: ($current_kernel), expected: (>= $MINIMUM_KERNEL_VERSION)."
        return 1
    fi

    # Verify secure boot
    secure_boot_status=$(mokutil --sb)
    echo "SecureBoot Status: $secure_boot_status"

    echo "Kernel and SecureBoot verified successfully, start driver installation."
    echo "Start gpu driver log."

    # Add NVIDIA CUDA repository keyring
    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(lsb_release -rs | tr -d '.')/x86_64/cuda-keyring_1.1-1_all.deb -o /tmp/cuda-keyring.deb
    sudo dpkg -i /tmp/cuda-keyring.deb
    rm -f /tmp/cuda-keyring.deb

    # Pin nvidia-modprobe to the 590 branch so `apt upgrade` never bumps it to
    # 595+. Priority 1001 also blocks auto-upgrades pulled in as dependencies.
    # 590.x patch updates are still allowed.
    printf 'Package: nvidia-modprobe\nPin: version 590.*\nPin-Priority: 1001\n' \
        | sudo tee /etc/apt/preferences.d/nvidia-pin-590.pref >/dev/null

    # Install dependencies
    sudo apt-get $APT_OPTS update
    sudo apt-get $APT_OPTS install -y initramfs-tools gcc g++ make

    # Apply change to modprobe.d and run update-initramfs
    echo 'install nvidia /sbin/modprobe ecdsa_generic ecdh; /sbin/modprobe --ignore-install nvidia' \
        | sudo tee /etc/modprobe.d/nvidia-lkca.conf >/dev/null
    sudo update-initramfs -u -k $current_kernel

    # Config Nvidia persistence daemon
    sudo mkdir -p /etc/needrestart/conf.d
    echo '$nrconf{"override_rc"}{"nvidia-persistenced.service"} = 0;' \
        | sudo tee /etc/needrestart/conf.d/99-skip-nvidia-persistenced.conf
    sudo install -d -m 0755 /etc/systemd/system/nvidia-persistenced.service.d
    sudo install -m 0644 "$SCRIPT_DIR/nvidia-persistenced.override.conf" /etc/systemd/system/nvidia-persistenced.service.d/override.conf
    sudo systemctl daemon-reload

    # Install r590 nvidia driver
    sudo apt-get -o APT::Get::Always-Include-Phased-Updates=true $APT_OPTS install -y \
        'nvidia-modprobe=590.*' \
        nvidia-driver-590-server-open \
        linux-modules-nvidia-590-server-open-azure-fde

    # Add check user nvidia-persistenced, fail if not exist
    id nvidia-persistenced

    # Load nvidia modules and start Nvidia persistence daemon
    load_nvidia_modules
    sudo usermod -aG root nvidia-persistenced
    if systemctl is-active --quiet nvidia-persistenced.service; then
        echo "nvidia-persistenced already running; skip start."
    else
        sudo systemctl start nvidia-persistenced.service
    fi
    sudo systemctl status nvidia-persistenced.service --no-pager -l || true

    # Print nvidia-smi info
    echo "Nvidia driver installation completed. nvidia-smi output:"
    nvidia-smi
    nvidia-smi conf-compute -q
}

load_nvidia_modules() {
    # Require nvidia-modprobe
    if ! command -v nvidia-modprobe >/dev/null 2>&1; then
        echo "ERROR: nvidia-modprobe not found" >&2
        exit 1
    fi

    # Load Nvidia kernel modules
    sudo modprobe nvidia
    sudo modprobe nvidia_uvm
    sudo modprobe nvidia_modeset

    # Create Nvidia device nodes
    sudo nvidia-modprobe -c 0          # /dev/nvidia0
    sudo nvidia-modprobe -c 255        # /dev/nvidiactl
    sudo nvidia-modprobe -m            # /dev/nvidia-modeset
    sudo nvidia-modprobe -u -c 0 -c 1  # /dev/nvidia-uvm + /dev/nvidia-uvm-tools

    # Post-check for /dev/nvidia0 and /dev/nvidiactl
    if [ ! -e /dev/nvidia0 ] || [ ! -e /dev/nvidiactl ]; then
        echo "ERROR: Nvidia device nodes not created" >&2
        exit 1
    fi
}

# Due to inconsistency upgrade from VM just booting up, adding 5 second delay.
sleep 5

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    echo -e "\n===== [step-1-install-gpu-driver.sh] $(date) =====" | tee logs/current-operation.log | tee -a logs/all-operation.log
    install_gpu_driver "$@" 2>&1 | tee -a logs/current-operation.log | tee -a logs/all-operation.log
fi
