## Introduction

The following steps help create a Confidential GPU Windows Virtual Machine with an H100 NVIDIA GPU and a Platform Managed Key (PMK) using manual instructions.

-----------------------------------------------

## Steps

- [Check-Requirements](#Check-Requirements)
- [Create-CGPU-VM](#Create-CGPU-VM)
- [Upload-Package](#Upload-Package)
- [Run-Onboarding-Package-Steps](#Run-Onboarding-Package-Steps)
- [Validation](#Validation)

-------------------------------------------

## Check-Requirements

Please make sure you have these requirements before performing the following steps: 
- [Azure Subscription](https://docs.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
  - This subscription needs to have been granted sufficient quotas for the NCC_H100_v5 SKU in order to successfully deploy any CGPU VMs
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
  - Note: minimum version 2.46.0 is required, run `az --version` to check your version and run `az upgrade` to install the latest version if your version is older
- Download [cgpu-onboarding-package.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V3.0.1/cgpu-onboardingpackage.tar.gz) from [Azure-Confidential-Computing-CGPUPrivatePreview-V3.0.1](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/tag/V3.0.1)

-------------------------------------------

## Create-CGPU-VM

1. Replace the following parameters with your own:
- $rg = your resource group name. If it does not already exist, it will create a new one
- $vmname = the name of the virtual machine you want to deploy
- $adminusername = the username you will use to log in to your virtual machine
- $publickeypath = the path to your local public key 
```
az vm create `
			--resource-group $rg `
			--name $vmname `
		  --image Canonical:0001-com-ubuntu-confidential-vm-jammy:22_04-lts-cvm:22.04.202312070 `
			--public-ip-sku Standard `
			--admin-username $adminusername `
			--ssh-key-values $publickeypath `
			--security-type ConfidentialVM `
			--os-disk-security-encryption-type DiskWithVMGuestState `
			--enable-secure-boot $true `
			--enable-vtpm $true `
			--size Standard_NCC40ads_H100_v5 `
			--os-disk-size-gb 100 `
			--verbose
```

----------------------------------------------------

## Upload-Package

1. Once your virtual machine is created, manually upload the cgpu-onboarding-package that you downloaded from the release:
- $privatekeypath = the path to your local private key 
- $cgpupackagepath = where you downloaded the onboarding package to
- $adminusername = the username you set to log in
- $vmip = the public IP address of your deployed virtual machine

```
scp -i $privatekeypath $cgpupackagepath $adminusername@$vmip:/home/${adminusername}

```

2. Log in to your virtual machine and extract the contents of the onboarding package

```
ssh -i ${privatekeypath} $adminusername@$vmip
tar -zxvf cgpu-onboarding-package.tar.gz
```

## Run-Onboarding-Package-Steps
1. Once the package has been extracted, enter the folder and run step 0 to prepare the kernel
```
cd cgpu-onboarding-package
bash step-0-prepare-kernel.sh
```

2. The next step will install the GPU driver. Please note that this step will involve a reboot
```
bash step-1-install-gpu-driver.sh
```

3. Once your virtual machine is up and running again, we are able to perform attestation by running the next step. You will be able to see the attestation message printed at the bottom
```
bash step-2-attestation.sh
```

4. Finally, run the last step to install the GPU tools. These are tools and packages that will allow you to run various workloads
```
bash step-3-install-gpu-tools.sh;
```

## Validation
In order to confirm that all the steps were performed successfully and to ensure that your CGPU VM is in the proper state, you can use the following commands:
1. Check whether secureboot is enabled. You should see: "SecureBoot enabled"
```
mokutil --sb-state
```

2. Check whether the confidential compute mode (CC Mode) is enabled. You should see: "CC status: ON"
``` 
nvidia-smi conf-compute -f
```

3. Check the confidential compute environment. You should see: "CC Environment: INTERNAL"
```
nvidia-smi conf-compute -e
```

## Workload-Running
Once you have finished the validation, you can execute the following commands to try a sample workload:

```
sudo docker run --gpus all -v /home/${adminusername}/cgpu-onboarding-package:/home -it --rm nvcr.io/nvidia/tensorflow:23.09-tf2-py3 python /home/mnist-sample-workload.py
```
