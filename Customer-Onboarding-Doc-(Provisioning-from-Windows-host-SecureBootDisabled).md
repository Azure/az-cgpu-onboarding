## Introduction

The following steps help create a Confidential GPU Virtual Machine with a Windows operating system.

-----------------------------------------------

## Steps

- [Create-CGPU-VM](#Create-CGPU-VM)
- [Install-GPU-Driver](#Install-GPU-Driver)
- [Attestation](#Attestation)
- [Workload-Running](#Workload-Running)

-------------------------------------------

## Requirements

- Windows
- Powershell: version 5.1.19041.1682 and above (please run windows powershell as administrator)
- [Azure Subscription](https://docs.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Download [cgpu-onboarding-package.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V1.0.2/cgpu-onboarding-package.tar.gz) from [Azure-Confidential-Computing-CGPUPrivatePreview-v1.0.2](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/tag/V1.0.2)

----------------------------------------------------

### Create-CGPU-VM

1. Prepare ssh key for creating VM (if you don't have one)

```
# id_rsa.pub will used as ssh-key-values for VM creation.
# id_rsa will be used for ssh in your vm
# replace <your email here> with your email address.
E:\cgpu\.ssh>ssh-keygen -t rsa -b 4096 -C <your email here>
Generating public/private rsa key pair.

Enter file in which to save the key (C:\Users\*****/.ssh/id_rsa): E:\cgpu\.ssh\id_rsa
e:\cgpu/.ssh/id_rsa already exists.

Overwrite (y/n)? y

Enter passphrase (empty for no passphrase):
Enter same passphrase again:

Your identification has been saved in E:\cgpu\.ssh\id_rsa.
Your public key has been saved in E:\cgpu\.ssh\id_rsa.pub.
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

2. Create VM using Azure CLI

```
# set your admin username
# note: username cannot contain upper case character A-Z, special characters \/"[]:|<>+=;,?*@#()! or start with $ or -
$adminusername="your user name"

# resource group name
$rg="your resource group name"

# VM name 
$vmname="your VM name"



# login in with your azure account
az login

# Check if you are on the right subscription
az account show

# switch subscriptions if needed
az account set --subscription [your subscriptionId]

# if you don't have a resource group already, execute this command to create one
az group create --name $rg --location eastus2


# create a VM.(takes few minute to finish)
# please replace <public key path> with your id_rsa.pub path
# eg: --ssh-key-values @E:\cgpu\.ssh\id_rsa.pub 
# create VM with (takes a few minute to finish)
az vm create `
--resource-group $rg `
--name $vmname `
--image Canonical:0001-com-ubuntu-server-focal:20_04-lts-gen2:20.04.202201310 `
--public-ip-sku Standard `
--admin-username $adminusername `
--ssh-key-values @<public key path> `
--security-type "TrustedLaunch" `
--enable-secure-boot $false `
--enable-vtpm $true `
--size Standard_NCC24ads_A100_v4 `
--os-disk-size-gb 100 `
--verbose

```

 3. Check your VM connection using your private key

```
# Use your private key file path generated in above and replace the [adminusername] and [IP] address below to connect to VM
# The IP address could be found in VM Azure Portal.
ssh -i <private key path> [adminusername]@[IP] -v
```

---------------

### Install-GPU-Driver

Download [cgpu-onboarding-package.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V1.0.2/cgpu-onboarding-package.tar.gz) from [Azure-Confidential-Computing-CGPUPrivatePreview-v1.0.2](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/tag/V1.0.2) if you haven't.

```
# In a separate local terminal not connected to your vm, upload cgpu-onboarding-package.tar.gz to your VM   
# Replace [adminusername] and [IP] with your admin user name and IP address
scp -i <private key path> cgpu-onboarding-package.tar.gz [adminusername]@[IP]:/home/[adminusername]

# In the terminal window connected to your VM, extract the onboarding folder from tar.gz, then step into the folder
tar -zxvf cgpu-onboarding-package.tar.gz
cd cgpu-onboarding-package 

# In the terminal window connected to your VM, install the GPU-Driver in cgpu-onboarding-package folder.
# This step also requires a reboot. Please wait about 5-10 min to reconnect to the VM
bash step-1-install-gpu-driver.sh

# After rebooting, reconnect to the VM. Recall it is as shown
ssh -i <private key path> [adminusername]@[IP] -v

# validate if the confidential compute mode is on.
# you should see "CC status: ON"
nvidia-smi conf-compute -f 

```

---------------

### Attestation

```
# In your VM, execute the attestation scripts in cgpu-onboarding-package.
# You should see: GPU 0 verified successfully.
cd cgpu-onboarding-package 
bash step-2-attestation.sh
```

-----------------

### Workload-Running

```
# In your VM, execute the install gpu tools script to pull down dependencies
cd cgpu-onboarding-package 
bash step-3-install-gpu-tools.sh

# Replace the [adminusername] with your admin username, then try to execute this sample workload with docker.
# It will download docker image if it couldn't find it.
sudo docker run --gpus all -v /home/[adminusername]/cgpu-onboarding-package:/home -it --rm nvcr.io/nvidia/tensorflow:21.10-tf2-py3 python /home/mnist-sample-workload.py

```
