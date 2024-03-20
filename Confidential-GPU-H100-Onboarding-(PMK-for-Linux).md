## Introduction

The following steps help create a Confidential GPU Linux Virtual Machine with an H100 NVIDIA GPU.
This page is using platform managed keys. More information about platform managed keys can be found here: 
[Azure Key Management](https://learn.microsoft.com/en-us/azure/security/fundamentals/key-management).

-----------------------------------------------

## Steps

- [Check-Requirements](#Check-Requirements)
- [Create-CGPU-VM](#Create-CGPU-VM)
- [Attestation](#Attestation)
- [Workload-Running](#Workload-Running)

-------------------------------------------

## Check-Requirements

- [Azure Subscription](https://docs.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
- [Azure Tenant ID](https://learn.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-how-to-find-tenant#find-tenant-id-with-powershell)
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
  - Note: minimum version 2.42.0 is required, run `az --version` to check your version and run `az upgrade` to install the latest version if your version is older
- Download [cgpu-h100-auto-onboarding-linux.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V3.0.2/cgpu-h100-auto-onboarding-linux.tar.gz) from [Azure-Confidential-Computing-CGPUPrivatePreview-V3.0.2](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/latest)

----------------------------------------------------

### Create-CGPU-VM

1. Prepare ssh key for creating VM (if you don't have one)
- Make sure to store your passphrase for later if using one

```
# id_rsa.pub will used as ssh-key-values for VM creation.
# id_rsa will be used for ssh in your vm.
# replace <your email here> with your email address.

E:\cgpu\.ssh>ssh-keygen -t rsa -b 4096 -C <your email here>
```

2. Create VM using powershell script
- This will create a Standard_NCC40ads_H100_v5 Confidential VM with a Platform Managed Key (PMK) with secure boot enabled in your specified resource group. If the resource group doesn't exist, it will create it with the specified name under the target subscription.

- Decompress downloaded [cgpu-h100-auto-onboarding-linux.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V3.0.2/cgpu-h100-auto-onboarding-linux.tar.gz) and enter the folder through your bash window.
```
cd cgpu-h100-auto-onboarding-linux
```

- Execute cgpu H100 onboarding script.
```
# Required Arguments: 
#	-t <tenant ID>: ID of your Tenant/Directory
#	-s <subscription ID>: ID of your subscription.
#	-r <resource group name>: The resource group name for VM creation
#                          It will create the Resource Group if it is not found under given subscription
#	-p <public key path>: your id_rsa.pub path 
#	-i <private key path>: your id_rsa path
#	-c <CustomerOnboardingPackage path>: Customer onboarding package path
#	-a <admin user name>: the username you'll use to log in to the VM
#	-v <vm name>: your VM name
#	-n <vm number>: number of VMs to be generated

bash cgpu-h100-auto-onboarding.sh  \
-t "<your Tenant ID>" \
-s "<your subscription ID>" \
-r "confidential-gpu-rg" \
-a "<your login username>" \
-p "/home/username/.ssh/id_rsa.pub" \
-i "/home/username/.ssh/id_rsa"  \
-c "./cgpu-onboarding-package.tar.gz" \
-v "cgpu-test"  \
-n 1
```

- This is a sample output that you will see at the end of a successful deployment: 
```
Finish install gpu tools.
Started C-GPU capable validation.
Passed: secure boot state validation. Current secure boot state: SecureBoot enabled
Passed: Confidential Compute mode validation passed. Current Confidential Compute retrieve state: CC status: ON
Passed: Confidential Compute environment validation. Current Confidential Compute environment: CC Environment: PRODUCTION
Finished C-GPU capable validation.
Finished creating VM: cgpu-01-12-7-1
******************************************************************************************
Please execute below commands to login to your VM(s):
ssh -i E:\cgpu\.ssh\id_rsa adminusername@20.114.244.82
Please execute the below command to try attestation:
cd cgpu-onboarding-package; bash step-2-attestation.sh
Please execute the below command to try a sample workload:
sudo docker run --gpus all -v /home/<adminusername>/cgpu-onboarding-package:/home -it --rm nvcr.io/nvidia/tensorflow:24.02-tf2-py3 python /home/mnist-sample-workload.py
******************************************************************************************
Total VM to onboard: 1, total Success: 1.
Detailed logs can be found at: .\logs\01-12-2024_14-42-44
Transcript stopped, output file is D:\repo\PrivatePreview\drops\cgpu-h100-onboarding\logs\01-12-2024_14-42-44\current-operation.log

------------------------------------------------------------------------------------------
```
### Attestation
Please run this command every time after rebooting your machine.
```
# In your VM, execute the attestation scripts in cgpu-onboarding-package.
# You should see: GPU 0 verified successfully.

cd cgpu-onboarding-package 
bash step-2-attestation.sh
```

### Workload-Running

```
# In your VM, execute the below command for a tensorflow sample execution.

sudo docker run --gpus all -v /home/<adminusername>/cgpu-onboarding-package:/home -it --rm nvcr.io/nvidia/tensorflow:24.02-tf2-py3 python /home/mnist-sample-workload.py
```
