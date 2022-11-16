## Introduction

The following steps help create a [Azure Secure Boot](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-portal-subscription-admin) enabled Confidential GPU Virtual Machine with a Linux operating system.

-----------------------------------------------


## Steps

- [Create-CGPU-VM](#Create-CGPU-VM)
- [Attestation](#Attestation)
- [Workload-Running](#Workload-Running)



## Requirements

- Linux
- [Azure Subscription](https://docs.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Download [cgpu-sb-enable-vmi-onboarding.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V1.0.7/cgpu-sb-enable-vmi-onboarding.tar.gz) from [Azure-Confidential-Computing-CGPUPrivatePreview-V1.0.7](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/tag/V1.0.7)


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

2. Provision Service Principal (First Time Only)


```
# Please contact Azure Confidential Computing Team to get your <service principal ID> and <secret> for the Image Access.
# Giving tenant access to the image requires provisioning a Service Principal into your tenant by requesting a sign-in using a browser. 
# In the below link, replace <tenant ID> with your tenant ID for the tenant that you would like to create the VM with. 
# Replace <service principal ID> with the service principal ID that Microsoft shared with you. 
# When done making the replacements, paste the URL into a browser and follow the sign-in prompts to sign into your tenant.

https://login.microsoftonline.com/<tenant ID>/oauth2/authorize?client_id=<service principal ID>&response_type=code&redirect_uri=https%3A%2F%2Fwww.microsoft.com%2F 
```

3. Create VM Based on confidential capable VM

- Decompress downloaded [cgpu-sb-enable-vmi-onboarding.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V1.0.7/cgpu-sb-enable-vmi-onboarding.tar.gz) and enter the folder.
```
tar -zxvf cgpu-sb-enable-vmi-onboarding.tar.gz
cd cgpu-sb-enable-vmi-onboarding
```

- Execute cgpu onboarding script.
Note: First time deployment will need subscription owner/administrator to execute the script. ([Learn about owner/administrator role](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-portal-subscription-admin))
```
# This script will help to get you authenticated with Microsoft tenant 
# and get access to a private Canonical-signed confidential GPU-capable image with an Nvidia GPU driver already installed.
# Then it will launch VMs with secure boot enabled, based on the provided arguments in your specified resource group.
# If resource group doesn't exist, it will create the resource group with the specified name in the target subsription.
#
# Note: First time execution will require the administrator role for the target Azure subscription to
# provision by generating the associated service principal contributor roles in your target resource group. 
#
# Required Arguments: 
#	-t <tenant ID>: ID of your Tenant/Directory
#	-s <subscription ID>: ID of your subscription.
#	-r <resource group name>: The resource group name for VM creation
#	-p <public key path>: your id_rsa.pub path 
#	-i <private key path>: your id_rsa path
#	-c <CustomerOnboardingPackage path>: Customer onboarding package path
#	-a <admin user name>: administrator username for the VM
#	-s <service principal id>: your service principal ID you got from Microsoft
#	-x <secret>: your service principal secrect you got from Microsoft
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
# -c "/cgpu-onboarding-package.tar.gz" \
# -a "azuretestuser" \
# -d "4082afe7-2bca-4f09-8cd1-a584c0520589" \
# -x "FBw8......." \
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
-d "<sevice principal id>" \
-x "<secret>" \
-v "<vm name>"  \
-n <vm number>

Sample output:
******************************************************************************************
Please execute below command to login to your VM and try attestation:
ssh -i /home/xiaobwan/.ssh/id_rsa xiaobwan@172.177.164.26
cd cgpu-onboarding-package; bash step-2-attestation.sh
------------------------------------------------------------------------------------------
Please execute below command to login to your VM and try a sample workload:
ssh -i /home/xiaobwan/.ssh/id_rsa xiaobwan@172.177.164.26
bash mnist_example.sh pytorch
******************************************************************************************
Validate Confidential GPU capability.
connected
Passed: kernel validation. Current kernel: 5.15.0-1019-azure
Passed: secure boot state validation. Current secure boot state: SecureBoot enabled
Passed: Confidential Compute mode validation passed. Current Confidential Compute retrieve is CC status: ON
Passed: Confidential Compute environment validation. current Confidential Compute environment is CC Environment: INTERNAL
Passed: Attestation validation passed. last attestation message: GPU 0 verified successfully.
Current number of VM finished: 1, total Success: 1.
Total VM to onboard: 1, total Success: 1.
------------------------------------------------------------------------------------------
# Optional: Clean up Contributor Role in your ResourceGroup.
# az login --tenant 72f988bf-86f1-41af-91ab-2d7cd011db47
# az role assignment delete --assignee 4082afe7-2bca-4f09-8cd1-a584c0520588 --role "Contributor" --resource-group confidential-gpu-rg
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



