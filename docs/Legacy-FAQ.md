# Legacy FAQ

## Q: Why is the kernel version locked?

A: Kernel version 6.2.0.1018 is the only working kernel with driver version 535.129.03. The latest Nvidia driver signed by Canonical does not have a signed RIM (Reference Integrity Manifest), which would case the GPU attestation to fail.


## Q: How to update existing Nvidia driver from r535 (535.129.03 from release-3.0.2) to r550 (550.54.15 from releases-3.0.3 and onwards)?

A: If you have created the VM using previous versions of onboarding packages, you can download the latest onboarding package and follow the steps below to update the Nvidia driver. It will also release the hold of the Linux kernel and update the kernel.

On the host:
```
# Download a clean H100 onboarding package from the latest release
https://github.com/Azure/az-cgpu-onboarding/releases/download/V3.2.3/cgpu-onboarding-package.tar.gz
 
# Upload it to your VM
scp -i <private key path> ".\cgpu-onboarding-package.tar.gz" <username>@<IP>:/home/<username>
```

Log in to your VM and run the following commands:
```
# Unzip the new CGPU onboarding package to home folder
tar -zxvf cgpu-onboarding-package.tar.gz; cd cgpu-onboarding-package

# Uninstall Nvidia r535 driver and unhold Linux kernel
sudo bash utilities-uninstall-r535-driver.sh

# Update Linux kernel, expect reboot after kernel update
sudo bash step-0-prepare-kernel.sh

# Install Nvidia r550 driver
cd ~/cgpu-onboarding-package; sudo bash step-1-install-gpu-driver.sh

# (Optionally) Run attestation
sudo bash step-2-attestation.sh

# (Optionally) Run sample workload from Docker
sudo docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -v ~/cgpu-onboarding-package:/home -it --rm nvcr.io/nvidia/tensorflow:24.05-tf2-py3 python /home/mnist-sample-workload.py
```
