## Steps

- [Create-CGPU-VM](#Create-CGPU-VM)
- [Install-GPU-Driver](#Install-GPU-Driver) 
- [Attestation ](#Attestation) 
- [Workload-Running](#Workload-Running) 

------------------------------------------------

## requirements:

- Linux
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) 
- Download Files from [Azure-Confidential-Computing-CGPUPrivatePreview-v1.0.1](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/tag/V1.0.1 )
  - Source code (tar.gz) --> PrivatePreview-1.0.1.tar.gz
    (Contains templates to provision CGPU VM)
    
  - CgpuOnboardingPakcage.tar.gz
    (Contains tools to install CGPU Driver in VM)

----------------------------------------------------

### Create-CGPU-VM


1. Preparing ssh key for creating VM (If you don't have one)
```
E:\cgpu\.ssh>ssh-keygen -t rsa -b 4096 -C example@gmail.com
Generating public/private rsa key pair.
Enter file in which to save the key (C:\Users\soccerl/.ssh/id_rsa): e:\cgpu/.ssh/id_rsa
e:\cgpu/.ssh/id_rsa already exists.

Overwrite (y/n)? y
Enter passphrase (empty for no passphrase):
Enter same passphrase again:

Your identification has been saved in e:\cgpu/.ssh/id_rsa.
Your public key has been saved in e:\cgpu/.ssh/id_rsa.pub.
The key fingerprint is:
SHA256:YiPxu6SEIlIXmYKUzprXDhXqI13gLYmcyQzGNYGmdtk example@microsoft.com
The key's randomart image is:
+---[RSA 4096]----+
|..++.            |
|oB. oo           |
|%o+=B.           |
|oX=++E           |
|o+o=o = S        |
|+.*o.o +         |
|+o.+. o          |
|o. ..o .         |
|    . .          |
+----[SHA256]-----+
```
2. Executing VM Creation using Azure CLI
```
# extract PrivatePreview-1.0.1.tar.gz code go into the folder
tar -zxvf PrivatePreview-1.0.1.tar.gz
cd PrivatePreview-1.0.1

# azure admin user name
adminusername="your user name"

# resource group name
rg="your resource group name"

# vm name 
vmname="your vm name"

# login in with your azure account
Az login

# Check if you are on the right subscription
az account show

# switch subscription if needed.
az account set --subscription [your subscriptionId]

# if you don't have resource group, execute this command for creating an resource group
az group create --name $rg --location eastus2



# create VM with the provided template.json and parameter.json.(takes few minute to finish)
az deployment group create -g $rg -f "template.json" -p "parameters.json" -p cluster="bnz10prdgpc05" \
vmCount=1 \
deploymentPrefix=$vmname \
virtualMachineSize="NCC24ads_A100_v4" \
adminUsername=xiaobwan \
adminPublicKey="ssh-rsa AAAAB3NzaC1y.....(replace with your publickey)" \
platform=Linux \
linuxDistro=Ubuntu \
enableAN=$false \
installGpuDrivers=$false \
enableTVM=$false \
ubuntuRelease=20 \
OsDiskSize=100
```

 3. Check your vm connection using your private key.
```
# use your private key file path generated in above step to connect to VM.
# The IP address could be found in VM Azure Portal.
ssh -i <private key path> -v [adminusername]@20.94.81.45
```
---------------

### Install-GPU-Driver

```
# In local, Upload CgpuOnboardingPackage.tar.gz to your VM.
cd CgpuOnboardingRepo 
scp -i id_rsa CgpuOnboardingPackage.tar.gz -v [adminusername]@20.110.3.197:/home/[adminusername]

# In your VM, Extract onboarding folder from tar.gz, then step into the folder
tar -zxvf CgpuOnboardingPackage.tar.gz
cd CgpuOnboardingPackage 

# In your VM, Install right version kernel in CgpuOnboardingPackage folder.
# This step requires reboot. please wait about 2-5 min to reconnect to VM
bash step-1-install-kernel.sh

# After reboot, reconnect into VM and install GPU-Driver in CgpuOnboardingPackage folder.
# This step requires reboot. please wait about 2-5 min to reconnect to VM
cd CgpuOnboardingPackage 
bash step-2-install-gpu-driver.sh

# After reboot, reconnect into vm and validate if the confidential compute mode is on.
# you should see: CC status: ON
nvidia-smi conf-compute -f 

```
---------------

### Attestation
```
# In your VM, Execute attestation scripts in CgpuOnboardingPackage.
cd CgpuOnboardingPackage 
bash step-3-attestation.sh
```
you should see below verifier success.

-----------------
### Workload-Running

```
# In your VM, Execute install gpu tool scripts to pull associates dependencies
cd CgpuOnboardingPackage 
bash step-4-install-gpu-tools.sh

# Then try to execute sample workload with docker.
sudo docker run --gpus all -v /home/[your AdminUserName]/CgpuOnboardingPackage:/home -it --rm nvcr.io/nvidia/tensorflow:21.10-tf2-py3 python /home/unet_bosch_ms.py

```




