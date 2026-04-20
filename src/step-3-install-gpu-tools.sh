#!/usr/bin/env bash

## This module helps install Docker and NVIDIA Container Toolkit for executing GPU workloads.
##
## Requirements:
##      Minimum Nvidia driver:       v570.86.15
##
## Example:
##      sudo bash step-3-install-gpu-tools.sh
##

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Common apt-get options: lock timeout, retry limit, and network timeouts
APT_OPTS="-o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"

INSTALL_DOCKER=1
INSTALL_NVIDIA_CONTAINER_TOOLKIT=1
INSTALL_NVIDIA_DCGM=1

## Install Docker Engine.
install_docker() {
    echo "Start docker installation."
    sudo apt-get $APT_OPTS update
    sudo apt-get $APT_OPTS install -y ca-certificates curl gnupg lsb-release

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    sudo apt-get $APT_OPTS update
    sudo apt-get $APT_OPTS install -y docker-ce docker-ce-cli containerd.io

    sudo docker run hello-world
}

## Install NVIDIA Container Toolkit and configure Docker runtime.
install_nvidia_container_toolkit() {
    echo "Start NVIDIA Container Toolkit installation."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    sudo apt-get $APT_OPTS update
    sudo apt-get $APT_OPTS install -y \
        nvidia-container-toolkit \
        nvidia-container-toolkit-base \
        libnvidia-container-tools \
        libnvidia-container1

    # Nvidia currently having an issue with GPU disappear from docker
    # Put temp mitigation based on: https://github.com/nvidia/nvidia-container-toolkit/issues/48
    sudo echo "{ \"exec-opts\": [\"native.cgroupdriver=cgroupfs\"] }" | sudo tee /etc/docker/daemon.json

    # Configure Docker to use the NVIDIA runtime
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker

    # Configure nvidia-cdi-refresh service to run strictly after nvidia-persistenced
    sudo install -d -m 0755 /etc/systemd/system/nvidia-cdi-refresh.service.d
    sudo install -m 0644 "$SCRIPT_DIR/nvidia-persistenced-dependency.conf" /etc/systemd/system/nvidia-cdi-refresh.service.d/override.conf
    sudo systemctl daemon-reload
    sudo systemctl enable nvidia-cdi-refresh.service
    sudo systemctl start nvidia-cdi-refresh.service
    sudo systemctl status nvidia-cdi-refresh.service --no-pager -l || true

    sudo docker run --rm --runtime=nvidia --gpus all nvidia/cuda:13.1.1-base-ubuntu$(lsb_release -rs) nvidia-smi
}

## Install NVIDIA Data Center GPU Manager (DCGM) for GPU monitoring and diagnostics.
install_nvidia_dcgm() {
    echo "Start NVIDIA DCGM installation."

    # Detect the major CUDA version from the installed driver
    CUDA_VERSION=$(nvidia-smi | grep -oP 'CUDA Version: \K[0-9]+')
    echo "Detected CUDA major version: $CUDA_VERSION"

    sudo apt-get $APT_OPTS update
    sudo apt-get $APT_OPTS install -y \
        datacenter-gpu-manager-4-cuda${CUDA_VERSION} \
        datacenter-gpu-manager-4-core \
        datacenter-gpu-manager-4-proprietary \
        datacenter-gpu-manager-4-proprietary-cuda${CUDA_VERSION}

    # Configure nvidia-dcgm service to run strictly after nvidia-persistenced
    sudo install -d -m 0755 /etc/systemd/system/nvidia-dcgm.service.d
    sudo install -m 0644 "$SCRIPT_DIR/nvidia-persistenced-dependency.conf" /etc/systemd/system/nvidia-dcgm.service.d/override.conf
    sudo systemctl daemon-reload

    # Enable and start the DCGM service
    sudo systemctl --now enable nvidia-dcgm
    sudo systemctl status nvidia-dcgm --no-pager -l || true

    # Verify DCGM installation
    dcgmi discovery -l
    echo "NVIDIA DCGM installation complete."
}

## Install Nvidia GPU tools
install_gpu_tools() {
    if [ "$INSTALL_DOCKER" = "1" ]; then
        install_docker
    fi
    if [ "$INSTALL_NVIDIA_CONTAINER_TOOLKIT" = "1" ]; then
        install_nvidia_container_toolkit
    fi
    if [ "$INSTALL_NVIDIA_DCGM" = "1" ]; then
        install_nvidia_dcgm
    fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    echo -e "\n===== [step-3-install-gpu-tools.sh] $(date) =====" | tee logs/current-operation.log | tee -a logs/all-operation.log
    install_gpu_tools 2>&1 | tee -a logs/current-operation.log | tee -a logs/all-operation.log
fi
