## Introduction

The following steps help create a [Secure boot](https://docs.microsoft.com/en-us/azure/virtual-machines/trusted-launch) enabled Confidential GPU Virtual Machine with a Windows operating system.

-----------------------------------------------

## Steps

- [Create-CGPU-VM](#Create-CGPU-VM)
- [Enroll-Key-TVM](#Enroll-Key-TVM)
- [Install-GPU-Driver](#Install-GPU-Driver) 
- [Attestation ](#Attestation) 
- [Workload-Running](#Workload-Running) 

----------------------------------------

## Requirements

- Powershell: version 5.1.19041.1682 and above
- [Install Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) 
- Download Files from [Azure-Confidential-Computing-CGPUPrivatePreview-v1.0.1](https://github.com/Azure-Confidential-Computing/PrivatePreview/releases/tag/V1.0.1)
  - Source code (zip) --> CGPUPrivatePreview-1.0.1.zip
    (Contains templates to provision CGPU VM)

  - CgpuOnboardingPakcage.tar.gz
    (Contains tools to install CGPU Driver in VM)

-----------------------------------------


### Create-CGPU-VM

1. Prepare ssh key for creating VM (if you don't have one)
```
E:\cgpu\.ssh>ssh-keygen -t rsa -b 4096 -C example@gmail.com
Generating public/private rsa key pair.

Enter file in which to save the key (C:\Users\soccerl/.ssh/id_rsa): e:\cgpu/.ssh/id_rsa
e:\cgpu/.ssh/id_rsa already exists.

Overwrite (y/n)? y

Enter passphrase (empty for no passphrase):
Enter same passphrase again:

Your identification has been saved in e:\cgpu/.ssh/id_rsa.
Your public key has been saved in e:\cgpu/.ssh/id_rsa.pub.
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


2. Create VM using Azure CLI
```
# extract PrivatePreview-1.0.1.zip code go into the folder
cd PrivatePreview-1.0.1

# azure admin user name
$adminusername="your user name"

# resource group name
$rg="your resource group name"

# vm name 
$vmname="your vm name"

# ssh pub key generated from step1.
$SshCreds="ssh-rsa AAAAB3NzaC..."



# login in with your azure account
Az login

# Check if you are on the right subscription
az account show

# switch subscription if needed.
az account set --subscription [your subscriptionId]

# if you don't have resource group, execute this command for creating an resource group
az group create --name $rg --location eastus2


# create VM with the provided template.json and parameter.json.(takes few minute to finish)
az deployment group create -g $rg -f "template.json" -p "parameters.json" -p cluster="bnz10prdgpc05" `
vmCount=1 `
deploymentPrefix=$vmname `
virtualMachineSize="NCC24ads_A100_v4" `
adminUsername=$adminusername `
adminPublicKey=$SshCreds `
platform=Linux `
linuxDistro=Ubuntu `
enableAN=$false `
installGpuDrivers=$false `
enableTVM=$true `
ubuntuRelease=20 `
OsDiskSize=100

```
 3. Check your VM connection using your private key and verify secure boot enabled. 
```
# use your private key file path generated in above step to connect to VM.
# The IP address could be found in VM Azure Portal.
ssh -i <private key path> -v [adminusername]@20.94.81.45

# check security boot state, you should see : SecureBoot enabled
mokutil --sb-state

# Success: /dev/tpm0, Failure: ls: cannot access '/dev/tpm0': No such file or directory
ls /dev/tpm0
```



----------------------------------------------------------------

### Enroll-Key-TVM
```
# In local, upload CgpuOnboardingPackage.tar.gz to your VM.
scp -i id_rsa CgpuOnboardingPackage.tar.gz -v [adminusername]@20.110.3.197:/home/[adminusername]

# In your VM, create a password for the user if it is not already set
sudo passwd [adminusername]

# In your VM, extract the onboarding folder from tar.gz, then step into the folder
tar -zxvf CgpuOnboardingPackage.tar.gz

# Execute the following script to import nvidia signing key.
cd CgpuOnboardingPackage 
bash step-0-install-kernel.sh

```
- Go to your VM portal to set the boot diagnostics. 
- This update process may take several minutes to propagate.
![image.png](attachment/boot_diagnostics.JPG)

- You can select existing one or create a new one with default configuration.
![image.png](attachment/enable_storage_account.JPG)

- Go to the Serial Console and login with your adminUserName and password
![image.png](attachment/serial_console.JPG)

- Reboot the machine from Azure Serial Console by typing sudo reboot. A 10 second countdown will begin. Press up or down key to interrupt the countdown and wait in UEFI console mode. If the timer is not interrupted, the boot process continues and all of the MOK changes are lost. Select: Enroll MOK -> Continue -> Yes -> Enter your signing key password ->  Reboot.
![image.png](attachment/enrole_key.JPG)

----------------------------------------------------------------


### Install-GPU-Driver


```
# After the reboot is finished, ssh into your VM and install the right version kernel folder.
# This step requires a reboot. Afterwards, please wait about 2-5 minutes to reconnect to the VM
cd CgpuOnboardingPackage 
bash step-1-install-kernel.sh

# After rebooting, reconnect to the VM and install GPU-Driver in CgpuOnboardingPackage folder.
# This step also requires a reboot. Please wait about 2-5 min to reconnect to the VM
cd CgpuOnboardingPackage 
bash step-2-install-gpu-driver.sh

# After rebooting, reconnect to the VM and validate if the confidential compute mode is on.
# You should see: CC status: ON
nvidia-smi conf-compute -f 

```


----------------------------------------------------------------


### Attestation
```
# In your VM, execute attestation scripts in CgpuOnboardingPackage.
# You should see: GPU 0 verified successfully.
cd CgpuOnboardingPackage 
bash step-3-attestation.sh
```

-----------------

### Workload-Running

```
# In your VM, execute install gpu tool scripts to pull associates dependencies
cd CgpuOnboardingPackage 
bash step-4-install-gpu-tools.sh

# Then try to execute sample workload with docker.
sudo docker run --gpus all -v /home/[your AdminUserName]/CgpuOnboardingPackage:/home -it --rm nvcr.io/nvidia/tensorflow:21.10-tf2-py3 python /home/unet_bosch_ms.py

```



