## This module helps install gpu nvdia docker image for helping execute machine learning workload. 
##
## Requirements: 
##      nvdia driver:       APM_470.10.08_5.11.0-1028.31.tar
##      kenrel version:     5.11.0-1028-azure
##
## Example:
##      bash step-4-install-gpu-tools.sh
##


## install dockder dependency.
install_gpu_tools(){

    attestation_result=$(bash step-3-attestation.sh | tail -1| sed -e 's/^[[:space:]]*//')
    attestation_result=${attestation_result##*( )}
    if [ "$attestation_result" != "GPU 0 verified successfully." ]; 
    then
      echo "Current gpu attestation failed: ${attestation_result}, expected: GPU 0 verified successfully."
      echo "Please verify previous steps and retry attestation."
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
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

      sudo apt-get update -y
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io

      sudo docker run hello-world

      # Nvidia Container Toolkit
      distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
            && curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
            && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
                  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

      curl -s -L https://nvidia.github.io/libnvidia-container/experimental/$distribution/libnvidia-container.list | \
              sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
              sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

      sudo apt-get update
      sudo apt-get install -y nvidia-docker2
      sudo systemctl restart docker

      sudo docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
    fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    install_gpu_tools "$@"
fi
