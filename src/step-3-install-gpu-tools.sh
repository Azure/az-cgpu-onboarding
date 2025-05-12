## This module helps install gpu nvdia docker image for helping execute machine learning workload.
##
## Requirements:
##      Minimum Nvidia driver:       v570.86.15
##
## Example:
##      sudo bash step-3-install-gpu-tools.sh
##

ATTESTATION_SUCCESS_MESSAGE="GPU Attested Successfully"

## install dockder dependency.
install_gpu_tools() {
    echo "Start docker installation."
    # Install Docker
    sudo apt-get -o DPkg::Lock::Timeout=300 update
    sudo apt-get -o DPkg::Lock::Timeout=300 install -y ca-certificates curl gnupg lsb-release

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    sudo apt-get -o DPkg::Lock::Timeout=300 update
    sudo apt-get -o DPkg::Lock::Timeout=300 install -y docker-ce docker-ce-cli containerd.io

    sudo docker run hello-world

    # Nvidia Container Toolkit
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/libnvidia-container.list |
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    sudo apt-get -o DPkg::Lock::Timeout=300 update
    sudo apt-get -o DPkg::Lock::Timeout=300 install -y nvidia-docker2

    # Nvidia currently having an issue with GPU disappear from docker
    # Put temp mitigation based on: https://github.com/nvidia/nvidia-container-toolkit/issues/48
    sudo echo "{ \"exec-opts\": [\"native.cgroupdriver=cgroupfs\"] }" | sudo tee /etc/docker/daemon.json
    sudo systemctl restart docker

    sudo docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    install_gpu_tools "$@" 2>&1 | tee logs/current-operation.log | tee -a logs/all-operation.log
fi
