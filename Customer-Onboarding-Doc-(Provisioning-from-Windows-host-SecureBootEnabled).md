## Introduction

The following steps help create a Secureboot enabled Confidential GPU Virtual Machine with a Linux operating system.

-----------------------------------------------


## Steps

- [Create-CGPU-VM](#Create-CGPU-VM)
- [Attestation](#Attestation)
- [Workload-Running](#Workload-Running)



## Requirements

- Linux
- [Azure Subscription](https://docs.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Download [cgpu-onboarding-package.tar.gz](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V1.0.6/cgpu-onboarding-package.tar.gz) from [Azure-Confidential-Computing-CGPUPrivatePreview-V1.0.6](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/tag/V1.0.6)


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

2. Provision Service Pricipal(First Time Only)

```
Please contact Microsoft Confidential Team to get <sevice principal id> and <secret> for the Image Access.
Give Tenant access to the image requires provision Service Prinsipal into your tenant by requesting a sign-in using a browser. Replace <tenant id> with the your tenant id for the tenant that you would like to create the vm. Replace <service principal id> with the service principal id Microsoft shared with you. When done making the replacements, paste the URL into a browser and follow the sign-in prompts to sign into your tenant.

https://login.microsoftonline.com/<tenant id>/oauth2/authorize?client_id=<service principal id>&response_type=code&redirect_uri=https%3A%2F%2Fwww.microsoft.com%2F 
```

3. Create VM Based On confidential capable VM
```
# This Scripts will help to get authenticated with microsoft tenant 
# and get access to a private Cononical Signed Confidential Gpu capable Image with Nvidia GPU driver installed.
# Then it will lanucn SecureBoot Enabled VMs based on provided argument in specified resource group.
#
# First time execution will required administrator role for the target Azure subsciption to
# provision ServicePricipal into target Tenant and to generate associate serviceprincipal roles in target 
# resource group. 
#
# Required Arguments: 
#	<tenant id>: Id of your Tenant/Directory. 
#	<subscription id>: Id of your subscription. 
#   <resource group name>: The resource group name for Vm creation.
#					       It will create ResourceGroup if it is not found under given subscription.
#	<public key path>: your id_rsa.pub path. 
#	<private key path>: your id_rsa path. 
#	<CustomerOnboardingPackage path>: Customer onboarding package path.
#	<admin user name>: Admin user name.
#	<vm name>: your VM name
#	<service principal id>: your service principal id you got from microsoft.
#	<secret>: your service principal secrect you got from microsoft.
#	<vm number>: number of vm to be generated.
#
# bash SecurebootEnableOnboarding.sh  \
# -t "8af6653d-c9c0-4957-ab01-615c7212a40b" \
# -s "9269f664-5a68-4aee-9498-40a701230eb2" \
# -r "confidential-gpu-rg" \
# -p "/home/username/.ssh/id_rsa.pub"  \
# -i "/home/username/.ssh/id_rsa"  \
# -c "/home/username/cgpu-onboarding-package.tar.gz" \
# -a "azuretestuser" \
# -v "confidential-test-vm"  \
# -d "4082afe7-2bca-4f09-8cd1-a584c0520589" \
# -x "FBw8......." \
# -n 1


bash SecurebootEnableOnboarding.sh  \
-t "<tenant id>" \
-s "<subscription id>" \
-r "<resource group name>" \
-p "<public key path>"  \
-i "<private key path>"  \
-c "<CustomerOnboardingPackage path>" \
-a "<admin user name>" \
-v "<vm name>"  \
-d "<sevice principal id>" \
-x "<secret>" \
-n <vm number>
```





