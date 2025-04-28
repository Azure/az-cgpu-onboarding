## This module helps install associate dependency and do attestation against CGPU driver.
##
## Requirements:
##      Minimum Nvidia driver:      v570.86.15
##      Minimum kernel version:     6.5.0-1017-azure
##
## Example:
##      sudo bash step-2-attestation.sh [--install-to-usr-local]
##

REQUIRED_DRIVER_INTERFACE_VERSION="570.86.15"
INSTALL_TO_USR_LOCAL=0

# Parse command-line arguments
if [ $# -ne 0 ]; then
    if [ "$1" = "--install-to-usr-local" ]; then
        INSTALL_TO_USR_LOCAL=1
    else
        echo "Invalid argument: $1"
        echo "Usage: $0 [--install-to-usr-local]"
        exit 1
    fi
fi

attestation() {
    # verify nvdia gpu driver has been install correctly.
    sudo nvidia-smi -pm 1
    current_driver_interface_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)
    echo -e "$REQUIRED_DRIVER_INTERFACE_VERSION\n$current_driver_interface_version" | sort --check=quiet --version-sort
    if [ "$?" -ne "0" ]; then
        echo "Current gpu driver version: $current_driver_interface_version, Expected: >= $REQUIRED_DRIVER_INTERFACE_VERSION."
        echo "Please retry step-1-install-gpu-driver."
    else
        echo "Current driver version: $current_driver_interface_version"

        # Install Python3 pip and venv
        sudo apt -o DPkg::Lock::Timeout=300 update
        sudo apt -o DPkg::Lock::Timeout=300 install -y python3-pip python3-venv

        # Install to /usr/local/lib
        if [ "$INSTALL_TO_USR_LOCAL" = "1" ]; then
            echo "Installing local_gpu_verifier in /usr/local/lib"

            # Remove existing folder if present
            if [ -d "/usr/local/lib/local_gpu_verifier" ]; then
                echo "Removing existing /usr/local/lib/local_gpu_verifier"
                sudo rm -rf "/usr/local/lib/local_gpu_verifier"
            fi

            sudo mkdir -p /usr/local/lib/local_gpu_verifier
            sudo tar -xvf local_gpu_verifier.tar -C /usr/local/lib/local_gpu_verifier
            pushd /usr/local/lib/local_gpu_verifier >/dev/null

        # Install to current folder
        else
            sudo mkdir -p local_gpu_verifier
            sudo tar -xvf local_gpu_verifier.tar -C local_gpu_verifier
            pushd ./local_gpu_verifier >/dev/null
        fi
        echo "Open verifier folder successfully!"

        sudo rm -rf ./prodtest
        sudo python3 -m venv ./prodtest
        sudo ./prodtest/bin/python3 -m pip install .
        sudo ./prodtest/bin/python3 -m verifier.cc_admin
        popd >/dev/null
    fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    attestation "$@" 2>&1 | tee logs/current-operation.log | tee -a logs/all-operation.log
fi
