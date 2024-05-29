## Introduction

The following steps help create a Confidential GPU Windows Virtual Machine with an H100 NVIDIA GPU.
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

- [Powershell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4#msi): version 5.1.19041.1682 and above (please run windows powershell as administrator)
- [Azure Subscription](https://docs.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
- [Azure Tenant ID](https://learn.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-how-to-find-tenant#find-tenant-id-with-powershell)
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
   - Note: minimum version 2.42.0 is required, run `az --version` to check your version and run `az upgrade` to install the latest version if your version is older
- Download [cgpu-h100-auto-onboarding-windows.zip](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V3.0.4/cgpu-h100-auto-onboarding-windows.zip) from [Azure-Confidential-Computing-CGPUPrivatePreview-V3.0.4](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/tag/V3.0.4)

----------------------------------------------------

## Create-CGPU-VM

1. Prepare ssh key for creating VM (if you don't have one)
- Make sure to store your passphrase for later if using one

```
# id_rsa.pub will used as ssh-key-values for VM creation.
# id_rsa will be used for ssh in your vm.
# replace <your email here> with your email address.

$ ssh-keygen -t rsa -b 4096 -C <your email here>
```

2. Create the VM using a powershell script
- This will create a Standard_NCC40ads_H100_v5 Confidential VM with a Platform Managed Key (PMK) with secure boot enabled in your specified resource group. If the resource group doesn't exist, it will create it with the specified name under the target subscription.

- Decompress downloaded [cgpu-h100-auto-onboarding-windows.zip](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V3.0.4/cgpu-h100-auto-onboarding-windows.zip) and enter the folder through powershell.
```
cd cgpu-h100-auto-onboarding-windows
```
- Execute the CGPU H100 onboarding script.
```
# Required parameters:
# tenantid: your tenant ID, also known as your directory ID
# subscriptionid: your subscription ID
# rg: name of your resource group
# adminusername: the username you'll use to log in 
# publickeypath: the path to your public key file on your local file system
# privatekeypath: the path to your private key file on your local file system
# cgpupackagepath: your cgpu-onboarding-package.tar.gz path
# vmnameprefix: the prefix of your vm. It will create from prefix1, prefix2, prefix3 till the number of VMs specified;
# totalvmnumber: the number of VMs you want to create

# Optional Arguments:
# location: the region your resources will be created in. Currently supported regions are EastUS2 and WestEurope. If left blank, they will default to EastUS2 region

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module .\cgpu-h100-auto-onboarding.ps1 -Force
CGPU-H100-Onboarding `
-tenantid "<your Tenant ID>" `
-subscriptionid "<your subscription ID>" `
-rg "cgpu-test-rg" `
-location "eastus2" `
-publickeypath "...\.ssh\id_rsa.pub" `
-privatekeypath "...\.ssh\id_rsa"  `
-cgpupackagepath "cgpu-onboarding-package.tar.gz" `
-adminusername "<your login username>" `
-vmnameprefix "cgpu-test" `
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
sudo docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -v /home/<adminusername>/cgpu-onboarding-package:/home -it --rm nvcr.io/nvidia/tensorflow:24.03-tf2-py3 python /home/mnist-sample-workload.py
******************************************************************************************
Total VM to onboard: 1, total Success: 1.
Detailed logs can be found at: .\logs\01-12-2024_14-42-44
Transcript stopped, output file is D:\repo\PrivatePreview\drops\cgpu-h100-onboarding\logs\01-12-2024_14-42-44\current-operation.log

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

sudo docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -v /home/<adminusername>/cgpu-onboarding-package:/home -it --rm nvcr.io/nvidia/tensorflow:24.03-tf2-py3 python /home/mnist-sample-workload.py
```
