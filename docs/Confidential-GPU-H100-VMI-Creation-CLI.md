## Introduction

The following steps help create a Confidential GPU Virtual Machine with an H100 NVIDIA GPU with either a Platform Managed Key (PMK) or a Customer Managed Key (CMK) using a community shared image in the Azure Compute Gallery.

Detailed documentation on features and limitations of the Compute Gallery's community images can be found here: [Community Gallery](https://learn.microsoft.com/en-us/azure/virtual-machines/share-gallery-community?tabs=cli)

-----------------------------------------------

## Steps

- [Check Requirements](#Check-Requirements)
- [Create CGPU VM using Azure CLI](#Create-CGPU-VM)
  - [Powershell](#powershell-instructions)
  - [Bash](#bash-instructions)
- [Attestation](#attestation)
- [Validation](#Validation)
- [Workload Running](#Workload-Running)

-------------------------------------------

## Check-Requirements

Please make sure you have these requirements before performing the following steps: 
- [Azure Subscription](https://docs.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
- [Quota for the NCC H100 v5 VM SKU](../Frequently-Asked-Questions.md#q-how-can-i-get-quota-for-creating-an-ncc-cgpu-vm)
- [Azure Tenant ID](https://learn.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-how-to-find-tenant#find-tenant-id-with-powershell)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed before proceeding with this option.
  - Note: minimum version 2.46.0 is required, run `az --version` to check your version and run `az upgrade` to install the latest version if your version is older

-------------------------------------------

## Create-CGPU-VM
1. Log in to your azure account and ensure you are under the right subscription that has quota for this VM:
```
az login
az account set --subscription <your subscription ID>
```

2. If you would like to use a customer managed key (CMK), please follow the steps in [CMK-Instructions](./Confidential-GPU-H100-Onboarding-(CMK-with-Powershell).md#Prepare-Customer-Managed-Key) first.

3. Deploy an NCC40 CGPU VM by replacing the following parameters with your own:

Required Parameters:
- $rg = your resource group name. If it does not already exist, it will create a new one
- $vmname = the name of the virtual machine you want to deploy
- $location = the region you would like to deploy to. Currently we support `eastus2` and `westeurope`
- $adminusername = the username you will use to log in to your virtual machine
- $publickeypath = the path to your local public key 
  - Example: `C:\Users\username\.ssh\id_rsa.pub`
- $image = your chosen option from supported distributions listed below:
  - Ubuntu22.04: `'/CommunityGalleries/cgpuimage-fd891222-80b4-4e20-92b0-84d8979b2be8/Images/cgpu-H100-2204-base-image/versions/latest'`
  - Ubuntu24.04: `'/CommunityGalleries/cgpuimage-fd891222-80b4-4e20-92b0-84d8979b2be8/Images/cgpu-H100-2404-base-image/versions/latest'`
  - Please use single quotes in your image reference
- $encryptiontype = can be set to `VMGuestStateOnly` or `DiskWithVMGuestState`

Additional optional parameters:
- $osdisksize = the size of your OS disk. We recommend setting it to 100GB or larger
- $diskencryptionsetid = if you are using a customer managed key, the disk encryption set ID in the following format: `/subscriptions/{subscription-id}/resourceGroups/{resource-group-name}/providers/Microsoft.Compute/diskEncryptionSets/{disk-encryption-set-name}`
  - Refer to the [CMK-Instructions](./Confidential-GPU-H100-Onboarding-(CMK-with-Powershell).md#Prepare-Customer-Managed-Key) if you would like to use a customer managed key

Please run the following commands to deploy your resource group and VM in either [Powershell](#powershell-instructions) or [Bash](#bash-instructions):

### Powershell Instructions

```powershell
# Powershell PMK Setup
az group create --name $rg --location $location

az vm create `
--resource-group $rg `
--name $vmname `
--location $location `
--image $image `
--public-ip-sku Standard `
--admin-username $adminusername `
--ssh-key-values $publickeypath `
--security-type ConfidentialVM `
--os-disk-security-encryption-type $encryptiontype `
--enable-secure-boot $true `
--enable-vtpm $true `
--size Standard_NCC40ads_H100_v5 `
--os-disk-size-gb $osdisksize `
--accept-term `
--verbose
```

If you would like to deploy using a customer managed key (CMK), add the following parameter:
```powershell
--os-disk-secure-vm-disk-encryption-set $diskencryptionsetid 
```

### Bash Instructions

```bash
# Bash PMK Setup:
az group create --name $rg --location $location

az vm create \
  --resource-group $rg \
  --name $vmname \
  --location $location \
  --image $image \
  --public-ip-sku Standard \
  --admin-username $adminusername \
  --ssh-key-values $publickeypath \
  --security-type ConfidentialVM \
  --os-disk-security-encryption-type $encryptiontype \
  --enable-secure-boot true \
  --enable-vtpm true \
  --size Standard_NCC40ads_H100_v5 \
  --os-disk-size-gb $os_disk_size \
  --accept-term \
  --verbose
```

If you would like to deploy using a customer managed key (CMK), add the following parameter:
```bash
--os-disk-secure-vm-disk-encryption-set $diskencryptionsetid 
```

## Attestation
Once your CGPU VM is up and running, you can connect and run the following command to run attestation:
```
sudo /usr/local/lib/local_gpu_verifier/prodtest/bin/python3 -m verifier.cc_admin
```

## Validation
Optionally, the following commands can be run to gather more information about the state of your CGPU VM:

1. Check whether secureboot is enabled:
```
mokutil --sb-state
```
You should see: "SecureBoot enabled"

2. Check whether the confidential compute mode (CC Mode) is enabled:
``` 
nvidia-smi conf-compute -f
```
You should see: "CC status: ON"

3. Check the confidential compute environment:
```
nvidia-smi conf-compute -e
```
You should see: "CC Environment: PRODUCTION"

4. List the GPU information:
```
nvidia-smi
```

## Workload-Running
Once you have finished the validation, you can execute the following commands to try a sample workload:

```
sudo docker run --runtime=nvidia --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu22.04 nvidia-smi
```

If you would like to run a more complex sample, you can download this repo within your CGPU VM and run the mnist workload:
```
git clone https://github.com/Azure/az-cgpu-onboarding.git

# Please replace <adminusername> with your username below:

sudo docker run --runtime=nvidia --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -v /home/<adminusername>/az-cgpu-onboarding:/home -it --rm nvcr.io/nvidia/pytorch:26.02-py3 python /home/src/mnist-sample-workload.py
```


If you have reached this point, congratulations! You have offically created an NCC40 CGPU VM!
