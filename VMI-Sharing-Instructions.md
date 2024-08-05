# Introductions
Here is an overview of how to capture a CGPU VM image and what are the options for sharing it. In general, creating a SIG is simpler than storing things in a container since those are shared on a subscription/tenant-basis. 

Please note that the Azure Compute Gallery's direct share feature is still in a preview, so is subject to their preview terms. To learn more about it, take a look at their documentation [here](https://learn.microsoft.com/en-us/azure/virtual-machines/share-gallery-direct?tabs=portaldirect)

# Sharing within a subscription
Option 1: Export image and VMGS file using a shared image gallery (SIG)
- `ConfidentialVM` security type is supported for encrypted image (`ConfidentialVMSupported` security type for encrypted images will fail)
- `ConfidentialVMSupported` security type is supported for unencrypted images
- Note: if you the VM was created with an encrypted disk and CMK flow, `Confidential Disk Encryption` must be set to `True`

# Sharing to other subscriptions
Option 1: share an unencrypted image using a SIG
- Needs to set security type to `ConfidentialVMSupported`

Option 2: share an encrypted image using azure storage
- The following is a workaround that allows you to create an encrypted image based off an existing VM, upload the disks to an azure storage container, and then create an image or VM based off that. This example uses a PMK flow: 
 
```
# Base resource to save as an image (e.g. from onboarding script)
$base_rg = "<your rg name>"
$base_vm_name = "<your vm name>"

az vm deallocate -g $base_rg -n $base_vm_name

$base_disk_name = $(az vm show -g $base_rg -n $base_vm_name | jq -r .storageProfile.osDisk.name)

# Export both the OS VHD and the VMGS file
$disk_uris = az disk grant-access --access-level Read --duration-in-seconds 3600 --name $base_disk_name --resource-group $base_rg --secure-vm-guest-state-sas
 
$disk_uri = $disk_uris | jq -r ".accessSas"
$vmgs_uri = $disk_uris | jq -r ".securityDataAccessSas"
 
# Copy both uris to a storage account
$storageAccountId = az storage account show -g "<storage account rg>" -n "<storage account name>" | jq -r .id
$vhd_uri = "https://<storage account>.blob.core.windows.net/path/to/dest.vhd"
$security_data_uri = "https://<storage account>.blob.core.windows.net/path/to/dest.vmgs"
$sas = "<storage account SAS token>"

.\azcopy copy $vmgs_uri $($security_data_uri + "?" + $sas) --s2s-preserve-access-tier=false
.\azcopy copy $disk_uri $($vhd_uri + "?" + $sas) --s2s-preserve-access-tier=false
 
# Destination resource to create from the base image - can be in a different subscription as long as you have access
$rg = "<your new rg name>"
$disk_name = "<your disk name>"
$vm_name = "<your new vm name>"
 
az group create -n $rg -l eastus2
az disk create -g $rg -n $disk_name --source $vhd_uri --security-data-uri $security_data_uri --security-type ConfidentialVM_DiskEncryptedWithPlatformKey --size-gb 100 --hyper-v-generation V2 --source-storage-account-id $storageAccountId
 
az vm create --resource-group $rg --name $vm_name --attach-os-disk $disk_name --public-ip-sku Standard --security-type ConfidentialVM --os-disk-security-encryption-type DiskWithVMGuestState --enable-secure-boot true --enable-vtpm true --size Standard_NCC40ads_H100_v5 --os-type Linux --verbose
```

# Future investigations:
There are still a few scenarios we want to look into:
1. Using non-Confidential VM to create the image: export the generalized vhd, upload to a storage blob, create an image definition using the portal, create image version, and add customer subscription/tenant to the direct share
2. Sharing CGPU image with integrity protected OS disk, unencrypted disk, and PMK flow outside the subscription/tenant