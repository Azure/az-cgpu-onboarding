## Introduction

The following steps help create a [Azure Secure Boot](https://learn.microsoft.com/en-us/azure/virtual-machines/trusted-launch) enabled Confidential GPU Virtual Machine with a Windows operating system.


-----------------------------------------------

## Steps

- [Create-CGPU-VM](#Create-CGPU-VM)
- [Attestation](#Attestation)
- [Workload-Running](#Workload-Running)

-------------------------------------------

## Requirements

- Windows
- Powershell: version 5.1.19041.1682 and above (please run windows powershell as administrator)
- [Azure Subscription](https://docs.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription)
- [Admin of Azure Subscription](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-portal-subscription-admin)
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Download [cgpu-sb-enable-vmi-onboarding.zip](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V2.1.0/cgpu-sb-enable-vmi-onboarding.zip) from [Azure-Confidential-Computing-CGPUPrivatePreview-V2.1.0](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/tag/V2.1.0)

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

- Decompress downloaded [cgpu-sb-enable-vmi-onboarding.zip](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/download/V2.1.0/cgpu-sb-enable-vmi-onboarding.zip) and enter the folder through powershell.
```
cd cgpu-sb-enable-vmi-onboarding
```

- Execute cgpu onboarding script.
Note: First time deployment will need subscription owner/administrator to execute the script to set up access to shared image. ([Learn about owner/administrator role](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-portal-subscription-admin))
If re-use the same resource group that has already been set up, no specific role required as the Service Principal already have associated access. 
```
# This script will help to get you authenticated with Microsoft tenant 
# and get access to a private Canonical-signed confidential GPU-capable image with an Nvidia GPU driver already installed.
# Then it will launch VMs with secure boot enabled, based on the provided arguments in your specified resource group.
# If resource group doesn't exist, it will create the resource group with the specified name in the target subsription.
#
# Note: First time execution will require the administrator role for the target Azure subscription to
# provision by generating the associated service principal contributor roles in your target resource group. 
#
# Example Arguments: 
#	-tenantid "8af6653d-c9c0-4957-ab01-615c7212a40b" `
#	-subscriptionid "9269f664-5a68-4aee-9498-40a701230eb2" `
#	-rg "cgpu-test-rg" `
#	-publickeypath "E:\cgpu\.ssh\id_rsa.pub" `
#	-privatekeypath "E:\cgpu\.ssh\id_rsa"  `
#	-cgpupackagepath ".\cgpu-onboarding-package.tar.gz" `
#	-adminusername "azuretestuser" `
#	-serviceprincipalid "4082afe7-2bca-4f09-8cd1-a584c0520588" `
#	-serviceprincipalsecret "FBw8..." `
#	-vmnameprefix "cgpu-test-vm" `
#	-totalvmnumber 1

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module .\secureboot-enable-onboarding-from-vmi.ps1
Secureboot-Enable-Onboarding-From-VMI `
-tenantid "<tenant id>" `
-subscriptionid "<subscription id>" `
-rg "<resource group name>" `
-publickeypath "<public key path>" `
-privatekeypath "<private key path>"  `
-cgpupackagepath "<customerOnboardingPackage path>" `
-adminusername "<admin username>" `
-serviceprincipalid "<sevice principal id>" `
-serviceprincipalsecret "<secret>" `
-vmnameprefix "<vm name>" `
-totalvmnumber <vm number>

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
# Optional: Clean up Contributor Role in your ResourceGroup.
# az login --tenant
# az role assignment delete --assignee ca75afe3-e329-4f2f-b845-e5de2534e5be --role \
Contributor\ --resource-group <resource group name>
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



