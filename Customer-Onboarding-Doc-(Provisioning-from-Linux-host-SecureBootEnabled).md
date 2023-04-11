## Introduction

The following steps help create a [Azure Secure Boot](https://learn.microsoft.com/en-us/azure/virtual-machines/trusted-launch) enabled Confidential GPU Virtual Machine with a Linux operating system.

-----------------------------------------------


## Steps

- [Create-CGPU-VM](#Create-CGPU-VM)
- [Attestation](#Attestation)
- [Workload-Running](#Workload-Running)



## Requirements

- Linux
- [Azure Subscription](https://docs.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
- [Azure Tenant ID](https://learn.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-how-to-find-tenant#find-tenant-id-with-powershell)
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Download [cgpu-sb-enable-vmi-onboarding.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V2.1.0/cgpu-sb-enable-vmi-onboarding.tar.gz) from [Azure-Confidential-Computing-CGPUPrivatePreview-V2.1.0](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/tag/V2.1.0)
- Please contact your Microsoft administrator to get access to the VM image


### Create-CGPU-VM

1. Prepare ssh key for creating VM (if you don't have one)

```
# id_rsa.pub will used as ssh-key-values for VM creation.
# id_rsa will be used for ssh in your vm.
# Replace <your email here> with your email address.
$ ssh-keygen -t rsa -b 4096 -C <your email here>
Generating public/private rsa key pair.

Enter file in which to save the key (/c/Users/*****/.ssh/id_rsa): /e/cgpu/.ssh/id_rsa
/e/cgpu/.ssh/id_rsa already exists.

Overwrite (y/n)? y
Enter passphrase (empty for no passphrase):
Enter same passphrase again:

Your identification has been saved in /e/cgpu/.ssh/id_rsa
Your public key has been saved in /e/cgpu/.ssh/id_rsa.pub
The key fingerprint is:
SHA256:jPDCUwOmopYt+G49tBX2zZdaGQYnb9pGufj8/w9JsEY example@microsoft.com
The key's randomart image is:
+---[RSA 4096]----+
|    o            |
|   o .    o .    |
|. . . o    =E.   |
|o.o. +o+   .Bo   |
|o+ .+.ooSo Bo=.  |
|... .o. . =.O. . |
|  .o o     B  o  |
| .. +     . o  . |
| ..  .       ...*|
+----[SHA256]-----+
```

2. Create VM

- Decompress downloaded [cgpu-sb-enable-vmi-onboarding.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V2.1.0/cgpu-sb-enable-vmi-onboarding.tar.gz) and enter the folder through bash window.
```
tar -zxvf cgpu-sb-enable-vmi-onboarding.tar.gz
cd cgpu-sb-enable-vmi-onboarding
```

- Execute cgpu onboarding script.

```
# This script will help to get you get access to a private Canonical-signed confidential GPU-capable image with an Nvidia GPU driver 
# installed. Based on the provided arguments, it will then create VMs with secure boot enabled in your specified resource group.
# If the resource group doesn't exist, it will create the resource group with the specified name in the target subsription.
#
# Required Arguments: 
#	-t <tenant ID>: ID of your Tenant/Directory
#	-s <subscription ID>: ID of your subscription
#	-r <resource group name>: The resource group name for VM creation
#	-p <public key path>: your id_rsa.pub path 
#	-i <private key path>: your id_rsa path
#	-c <CustomerOnboardingPackage path>: Customer onboarding package path
#	-a <admin user name>: administrator username for the VM
#	-v <vm name>: your VM name
#	-n <vm number>: number of VMs to be generated
#
# Example:
# bash secureboot-enable-onboarding-from-vmi.sh  \
# -t "8af6653d-c9c0-4957-ab01-615c7212a40b" \
# -s "9269f664-5a68-4aee-9498-40a701230eb2" \
# -r "confidential-gpu-rg" \
# -p "/home/username/.ssh/id_rsa.pub" \
# -i "/home/username/.ssh/id_rsa"  \
# -c "./cgpu-onboarding-package.tar.gz" \
# -a "azuretestuser" \
# -v "confidential-test-vm"  \
# -n 1

bash secureboot-enable-onboarding-from-vmi.sh  \
-t "<tenant id>" \
-s "<subscription id>" \
-r "<resource group name>" \
-p "<public key path>"  \
-i "<private key path>"  \
-c "<customerOnboardingPackage path>" \
-a "<admin username>" \
-v "<vm name>"  \
-n <vm number>

Sample output:
******************************************************************************************
Please execute below commands to login to your VM(s):
ssh -i /home/username/.ssh/id_rsa azuretestuser@IP
Please execute the below command to try attestation:
cd cgpu-onboarding-package; bash step-2-attestation.sh
Please execute the below command to try a sample workload:
cd; bash mnist_example.sh pytorch
******************************************************************************************
------------------------------------------------------------------------------------------
# Detailed logs can be found logs/<date time>
```

### Attestation

```
# In your VM, execute the attestation scripts in cgpu-onboarding-package.
# You should see: GPU 0 verified successfully.
cd cgpu-onboarding-package 
bash step-2-attestation.sh
```

### Workload-Running

```
# In your VM, execute the below command for a pytorch sample execution. (estimates finish in 10 min) 
bash mnist_example.sh pytorch
```


