## Introduction

The following steps help create a Confidential GPU Linux Virtual Machine with an H100 NVIDIA GPU.
This page is using a customer managed keys. More information about customer managed keys can be found here: 
[Azure Key Management](https://learn.microsoft.com/en-us/azure/security/fundamentals/key-management).

-----------------------------------------------

## Steps

- [Check-Prerequisites](#requirements)
- [Create-Customer-Managed-Key](#create-customer-managed-key)
- [Create-CGPU-VM](#Create-CGPU-VM)
- [Attestation](#Attestation)
- [Workload-Running](#Workload-Running)

-------------------------------------------

## Requirements

- Linux
- [Azure Subscription](https://docs.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
- [Azure Tenant ID](https://learn.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-how-to-find-tenant#find-tenant-id-with-powershell)
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
  - Note: minimum version 2.42.0 is required, run `az --version` to check your version and run `az upgrade` to install the latest version if your version is older
- Download [cgpu-sb-enable-vmi-onboarding.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V3.0.1/cgpu-sb-enable-vmi-onboarding.tar.gz) from [Azure-Confidential-Computing-CGPUPrivatePreview-V3.0.1](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/tag/V3.0.1)

-------------------------------------------

## Create Customer Managed Key

----------------------------------------------------

### Create-CGPU-VM

1. Prepare ssh key for creating VM (if you don't have one)

```
# id_rsa.pub will used as ssh-key-values for VM creation.
# id_rsa will be used for ssh in your vm.
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

2. Create VM using powershell script

```

- Decompress downloaded [cgpu-h100-onboarding.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V3.0.1/cgpu-h100-onboarding.tar.gz) and enter the folder through bash window.
```
cd cgpu-h100-onboarding
```

- Execute cgpu H100 onboarding script.

# This script will help to get you get access to a private Canonical-signed confidential GPU-capable image with an Nvidia GPU driver 
# installed. It will then create VMs with secure boot enabled in your specified resource group.
# If the resource group doesn't exist, it will create the resource group with the specified name in the target subsription.
#
# Required parameters:
# 	rg: name of your resource group. (please do az login to your subscription and create a resource group)
#	adminusername: your adminusername
#	publickeypath: your public key path
#	privatekeypath: your private key path
#	cgppackagepath: your cgpu-onboarding-pakcage.tar.gz path
#	vmnameprefix: the prefix of your vm. It will create from prefix1, prefix2, prefix3 till the number of VMs specified;
#	totalvmnumber: the number of VMs you want to create

```
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module .\cgpu-h100-auto-onboarding.ps1
 CGPU-H100-Onboarding `
-tenantid "8af6653d-c9c0-4957-ab01-615c7212a40b" `
-subscriptionid "9269f664-5a68-4aee-9498-40a701230eb2" `
-rg "cgpu-test-rg" `
-publickeypath "E:\cgpu\.ssh\id_rsa.pub" `
-privatekeypath "E:\cgpu\.ssh\id_rsa"  `
-cgpupackagepath "E:\cgpu\cgpu-onboarding-package.tar.gz" `
-adminusername "admin" `
-vmnameprefix "cgpu-test" `
-totalvmnumber 2
```
Sample output:

Started cgpu capable validation.
Passed: kernel validation. Current kernel: 5.15.0-1019-azure
Passed: secure boot state validation. Current secure boot state: SecureBoot enabled
Passed: Confidential Compute mode validation passed. Current Confidential Compute retrieve state: CC status: ON
Passed: Confidential Compute environment validation. Current Confidential Compute environment: CC Environment: INTERNAL
Passed: Attestation validation passed. Last attestation message: GPU 0 verified successfully.
Finished cgpu capable validation.
Finished creating VM: '<vm name>'
******************************************************************************************
Please execute below commands to login to your VM(s):
ssh -i E:\cgpu\.ssh\id_rsa azuretestuser@IP
Please execute the below command to try attestation:
cd cgpu-onboarding-package; bash step-2-attestation.sh
Please execute the below command to try a sample workload:
cd; bash mnist_example.sh pytorch
******************************************************************************************
Total VM to onboard: 2, total Success: 2.
------------------------------------------------------------------------------------------
Detailed logs can be found at: .\logs\<date time>
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
