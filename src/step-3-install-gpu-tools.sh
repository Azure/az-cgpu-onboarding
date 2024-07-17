## This module helps install gpu nvdia docker image for helping execute machine learning workload.
##
## Requirements:
##      Minimum Nvidia driver:       v550.54.14
##
## Example:
##      sudo bash step-3-install-gpu-tools.sh
##

ATTESTATION_SUCCESS_MESSAGE="GPU Attested Successfully"
MAX_RETRY=3

## install dockder dependency.
install_gpu_tools() {
    # verify attestation is given the correct result.
    attestation_result=$(bash step-2-attestation.sh | tail -1 | sed -e 's/^[[:space:]]*//')
    if [ "$attestation_result" != "$ATTESTATION_SUCCESS_MESSAGE" ]; then
        echo "Current gpu attestation failed: ${attestation_result}, expected: GPU 0 verified successfully."
        echo "Please verify previous steps and retry step-2-attestation."
    else
        echo "Attestation successfully, start docker installation."
        # Install Docker
        sudo apt-get update -y

        sudo apt-get install \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

        sudo apt-get update -y
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io

        sudo docker run hello-world

        # Nvidia Container Toolkit
        distribution=$(
            . /etc/os-release
            echo $ID$VERSION_ID
        ) &&
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&
            curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list |
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

        sudo apt-get update
        sudo apt-get install -y nvidia-docker2

        # Nvidia currently having an issue with GPU disappear from docker
        # Put temp mitigation based on: https://github.com/nvidia/nvidia-container-toolkit/issues/48
        sudo echo "{ \"exec-opts\": [\"native.cgroupdriver=cgroupfs\"] }" | sudo tee /etc/docker/daemon.json
        sudo systemctl restart docker

        sudo docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi

        lockError=$(cat logs/current-operation.log | grep "Could not get lock")
        if [ "$lockError" != "" ] && [ $MAX_RETRY \> 0 ]; then
            # start of retry, clean up current-operation log.
            MAX_RETRY=$((MAX_RETRY - 1)) >logs/current-operation.log
            echo "Found lock error retry install gpu tools step."
            echo "Retry left:"
            echo $MAX_RETRY
            sudo apt-get install -y libgl1 binutils xserver-xorg-core
            sudo apt --fix-broken install
            install_gpu_tools "$@"
        fi
    fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    install_gpu_tools "$@" 2>&1 | tee logs/current-operation.log | tee -a logs/all-operation.log
fi
