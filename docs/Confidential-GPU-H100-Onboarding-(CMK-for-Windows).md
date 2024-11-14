## Introduction

The following steps help create a Confidential GPU Virtual Machine with an H100 NVIDIA GPU.
This page is using a customer managed keys. More information about customer managed keys can be found here: 
[Azure Key Management](https://learn.microsoft.com/en-us/azure/security/fundamentals/key-management).

-----------------------------------------------

## Steps

- [Check-Requirements](#Check-Requirements)
- [Create-Customer-Managed-Key](#Prepare-customer-managed-key)
- [Create-CGPU-VM](#Create-CGPU-VM)
- [Attestation](#Attestation)
- [Workload-Running](#Workload-Running)

-------------------------------------------

## Check-Requirements

- [Powershell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4#msi): version 7 and above (please run windows powershell as administrator)
- [Azure Subscription](https://docs.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
- [Azure Tenant ID](https://learn.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-how-to-find-tenant#find-tenant-id-with-powershell)
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
   - Note: minimum version 2.42.0 is required, run `az --version` to check your version and run `az upgrade` to install the latest version if your version is older
- Download [cgpu-h100-auto-onboarding-windows.zip](https://github.com/Azure/az-cgpu-onboarding/releases/download/V3.1.21/cgpu-h100-auto-onboarding-windows.zip) from [az-cgpu-onboarding-V3.1.21](https://github.com/Azure/az-cgpu-onboarding/releases/tag/V3.1.21)

-------------------------------------------

## Prepare-Customer-Managed-Key

0. If you already have a CMK, you can get your desId through your desName and resourceGroup
```
  az disk-encryption-set show -n $desName -g $resourceGroup --query [id] -o tsv
```

1. If you do not have an existing CMK, please follow steps below to create a new one. Firstly, open Powershell as Admin and find the cmk module
```
cd <Repo Path>/src/cmk_module
```
Then follow the instructions in [src/cmk_module/README.md](src/cmk_module/README.md) to create a new CMK


----------------------------------------------------

## Create-CGPU-VM

1. Prepare ssh key for creating VM (if you don't have one)
- Make sure to store your passphrase for later if using one

```
# id_rsa.pub will used as ssh-key-values for VM creation.
# id_rsa will be used for ssh in your vm.
# replace <your email here> with your email address.

E:\cgpu\.ssh>ssh-keygen -t rsa -b 4096 -C <your email here>

```

2. Create VM using powershell script
- This will create a Standard_NCC40ads_H100_v5 Confidential VM with a Customer Managed Key (CMK) with secure boot enabled in your specified resource group. If the resource group doesn't exist, it will create it with the specified name under the target subscription.

- Decompress downloaded [cgpu-h100-auto-onboarding-windows.zip](https://github.com/Azure/az-cgpu-onboarding/releases/download/V3.1.21/cgpu-h100-auto-onboarding-windows.zip) and enter the folder through powershell.
```
cd cgpu-h100-auto-onboarding-windows
```

- Execute cgpu H100 onboarding script.
```
# Required parameters:
# tenantid: your tenant ID, also known as your directory ID
# subscriptionid: your subscription ID
# rg: name of your resource group. (please do az login to your subscription and create a resource group)
# adminusername: the username you'll use to log in
# publickeypath: your public key path
# privatekeypath: your private key path
# desid: disk encryption set ID (if not set, your VM will be created using a platform managed key)
# cgpupackagepath: your cgpu-onboarding-package.tar.gz path
# vmnameprefix: the prefix of your vm. It will create from prefix1, prefix2, prefix3 till the number of VMs specified;
# totalvmnumber: the number of VMs you want to create

# Optional Arguments:
# location: the region your resources will be created in. Currently supported regions are eastus2 and westeurope.
#            If left blank, they will default to eastus2 region
# osdisksize: the size of your OS disk. The current maximum supported size is 4095 GB
#                If left blank, it will default to 100 GB

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module .\cgpu-h100-auto-onboarding.ps1 -Force
CGPU-H100-Onboarding `
-tenantid "<your Tenant ID>" `
-subscriptionid "<your subscription ID>" `
-rg "cgpu-test-rg" `
-location "eastus2" `
-publickeypath "E:\cgpu\.ssh\id_rsa.pub" `
-privatekeypath "E:\cgpu\.ssh\id_rsa"  `
-desid "/subscriptions/85c61f94-8912-4e82-900e-6ab44de9bdf8/resourceGroups/CGPU-CMK-KV/providers/Microsoft.Compute/diskEncryptionSets/CMK-Test-Des-03-01" `
-cgpupackagepath "cgpu-onboarding-package.tar.gz" `
-adminusername "<your login username>" `
-vmnameprefix "cgpu-test" `
-osdisksize 100 `
-totalvmnumber 1
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
cd cgpu-onboarding-package; sudo bash step-2-attestation.sh
Please execute the below command to try a sample workload:
sudo docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -v /home/<adminusername>/cgpu-onboarding-package:/home -it --rm nvcr.io/nvidia/tensorflow:24.05-tf2-py3 python /home/mnist-sample-workload.py
******************************************************************************************
Total VM to onboard: 1, total Success: 1.
Detailed logs can be found at: .\logs\01-12-2024_14-42-44
Transcript stopped, output file is D:\repo\az-cgpu-onboarding\drops\cgpu-h100-onboarding\logs\01-12-2024_14-42-44\current-operation.log

------------------------------------------------------------------------------------------
```

## Attestation
Please run this command every time after rebooting your machine.
```
# In your VM, execute the attestation scripts in cgpu-onboarding-package.
# You should see: GPU 0 verified successfully.

cd cgpu-onboarding-package 
bash step-2-attestation.sh
```

## Workload-Running

```
# In your VM, execute the below command for a tensorflow sample execution.

sudo docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -v /home/<adminusername>/cgpu-onboarding-package:/home -it --rm nvcr.io/nvidia/tensorflow:24.05-tf2-py3 python /home/mnist-sample-workload.py
```
