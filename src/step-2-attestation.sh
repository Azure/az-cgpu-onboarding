## This module helps install associate dependency and do attestation against CGPU driver.
##
## Requirements:
##      Minimum Nvidia driver:      v550.90.07
##      Minimum kernel version:     6.5.0-1017-azure
##
## Example:
##      sudo bash step-2-attestation.sh
##

REQUIRED_DRIVER_INTERFACE_VERSION="NVIDIA System Management Interface -- v550.90.07"
MAX_RETRY=3

attestation() {
    # verify nvdia gpu driver has been install correctly.
    sudo nvidia-smi -pm 1
    current_driver_interface_version=$(sudo nvidia-smi -h | head -1)
    if [ "$current_driver_interface_version" != "$REQUIRED_DRIVER_INTERFACE_VERSION" ]; then
        echo "Current gpu driver version: ($current_driver_interface_version), Expected: ($REQUIRED_DRIVER_INTERFACE_VERSION)."
        echo "Please retry step-1-install-gpu-driver."
    else
        mkdir local_gpu_verifier
        tar -xvf local_gpu_verifier.tar -C local_gpu_verifier
        pushd .
        cd local_gpu_verifier && echo "Open verifier folder successfully!"

        sudo apt install -y python3-pip
        sudo pip install -U pip
        sudo apt install -y python3.10-venv

        #source ./prodtest/bin/activate
        sudo pip3 install .
        sudo python3 -m verifier.cc_admin
        popd >/dev/null

        lockError=$(cat logs/current-operation.log | grep "Could not get lock")
        if [ "$lockError" != "" ] && [ $MAX_RETRY \> 0 ]; then
            # start of retry, clean up current-operation log.
            MAX_RETRY=$((MAX_RETRY - 1)) >logs/current-operation.log
            echo "Found lock error retry attestation step."
            echo "Retry left:"
            echo $MAX_RETRY
            sudo apt-get install -y libgl1 binutils xserver-xorg-core
            sudo apt --fix-broken install
            attestation "$@"
        fi
    fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    attestation "$@" 2>&1 | tee logs/current-operation.log | tee -a logs/all-operation.log
fi
