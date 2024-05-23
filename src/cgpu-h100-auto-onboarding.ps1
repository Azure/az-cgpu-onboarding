# ----------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ----------------------------------------------------------------------------
#
# This Module helps onboard cgpu VMs in Window host.
#
# Onboarding Flow:
# 1: Create VM using Azure CLI.
# 2: Upload and prepare onboarding package to VM.
# 3: Validate kernel version and install CGPU driver.
# 4: Reboot and reconnect to VM
# 5: Attestation.
# 6: Install GPU docker tools.
# 7: Output connection ssh info and tensorflow execution command.
#
# Required parameters:
# 	rg: name of your resource group. (please do az login to your subscription and create a resource group)
#	adminusername: your adminusername
#	publickeypath: your public key path
#	privatekeypath: your private key path
#   desid: disk encryption set id. (only need if trying to use CMK, otherwith vm will be create through PMK)
#	cgppackagepath: your cgpu-onboarding-pakcage.tar.gz path
#	vmnameprefix: the prefix of your vm. It will create from prefix1, prefix2, prefix3 till the number of retry specified;
#	totalvmnumber: the number of retry we want to perform.
#
# Optional parameters:
#    location: the location of your resources (if not specified, the default is eastus2)
# 
# EG:
# CGPU-H100-Onboarding `
# -tenantid "8af6653d-c9c0-4957-ab01-615c7212a40b" `
# -subscriptionid "9269f664-5a68-4aee-9498-40a701230eb2" `
# -rg "cgpu-test-rg" `
# -location "eastus2" `
# -publickeypath "E:\cgpu\.ssh\id_rsa.pub" `
# -privatekeypath "E:\cgpu\.ssh\id_rsa"  `
# -desid "/subscriptions/85c61f94-8912-4e82-900e-6ab44de9bdf8/resourceGroups/CGPU-CMK-KV/providers/Microsoft.Compute/diskEncryptionSets/CMK-Test-Des-03-01" `
# -cgpupackagepath "E:\cgpu\cgpu-onboarding-package.tar.gz" `
# -adminusername "adminusername" `
# -vmnameprefix "cgpu-test" `
# -totalvmnumber 2

function CGPU-H100-Onboarding{
		param(
		$tenantid,
		$subscriptionid,
		$rg,
		$location,
		$publickeypath,
		$privatekeypath,
		$desid,
		$cgpupackagepath,
		$adminusername,
		$vmnameprefix,
		$totalvmnumber)

		$ONBOARDING_PACKAGE_VERSION="v3.0.4"
		Write-Host "Confidential GPU H100 Onboarding Package Version: $ONBOARDING_PACKAGE_VERSION"

		$logpath=$(Get-Date -Format "MM-dd-yyyy_HH-mm-ss")
		if (!(Test-Path ".\logs\$logpath\"))
		{
			New-Item -ItemType Directory -Force -Path ".\logs\$logpath\"
			Write-Host "Created log file directory"
		}
		
		try {
			# Attempt to get the version of Azure CLI
			$azVersion = az --version
			# If the command runs successfully, it means Azure CLI is installed
			Write-Output "Azure Cli is installed current on $(az --version | Select-String 'azure-cli')"
			# Make sure minimum Azure CLI version is met
	 		$currentAzCLIVersion = (az --version | Select-String -Pattern 'azure-cli.*?([0-9\.]+)').Matches.Groups[1].Value
	 		$minimumAzCLIVersion="2.47.0"
			if ([System.Version]$minimumAzCLIVersion -gt [System.Version]$currentAzCLIVersion) {
				Write-Host "Current Azure CLI version found: $currentAzCLIVersion, expected >=$minimumAzCLIVersion"
    				az upgrade
			}
		} catch {
			Write-Host "Azure CLI is not installed, please try install Azure CLI first: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?tabs=powershell"
			Write-Host "Note: you might need to restart powershell after install."
			return
		}

		Start-Transcript -Path .\logs\$logpath\current-operation.log -Append
		Auto-Onboard-CGPU-Multi-VM 
		trap {Stop-Transcript; break}
		Stop-Transcript
}


# Auto Create and Onboard Multiple CGPU VM for customer.
function Auto-Onboard-CGPU-Multi-VM {
	Write-Host "Tenant id: ${tenantid}"
	Write-Host "Subscription ID: ${subscriptionid}"
	Write-Host "Resource group: ${rg}"

	# Sets the location to eastus2 region if not otherwise specified
	if (-not $location) {
		$location = "eastus2"
		Write-Host "Location not specified, defaulting to eastus2 region."
	}
	elseif ($location -eq "eastus2" -Or $location -eq "westeurope") {
		Write-Host "Allowed location selected."
	}
	else {
		Write-Host "ERROR: That location is not allowed."
		return
	}
	Write-Host "Location: ${location}"

	Write-Host "Public key path:  ${publickeypath}"
	if (-not(Test-Path -Path $publickeypath -PathType Leaf)) {
		Write-Host "${public_key_path} does not exist, please verify file path"
	return
	}

	Write-Host "Private key path:  ${privatekeypath}"
	if (-not(Test-Path -Path $privatekeypath -PathType Leaf)) {
		Write-Host "${privatekeypath} does not exist, please verify file path"
	return
	}

	Write-Host "C-GPU onboarding package path:  ${cgpupackagepath}"
	if (-not(Test-Path -Path $cgpupackagepath -PathType Leaf)) {
		Write-Host "${cgpupackagepath} does not exist, please verify file path"
	return
	}

	Write-Host "Admin user name:  ${adminusername}"
	Write-Host "Disk encryption set:  ${desid}"
	Write-Host "Vm Name prefix:  ${vmnameprefix}"
	Write-Host "Total VM number:  ${totalvmnumber}"
	Write-Host "Clear previous account info."
	az account clear
	az login --tenant $tenantid 2>&1 | Out-File -filepath ".\logs\$logpath\login-operation.log"
	az account set --subscription $subscriptionid
	az account show

	$global:issuccess = "succeeded"
	Prepare-Subscription-And-Rg 2>&1 | Out-File -filepath ".\logs\$logpath\login-operation.log"
	if ($global:issuccess -eq "failed") {
		Write-Host "Prepare-Subscription-And-Rg Failed"
		return
	}
	else {
		Write-Host "Prepare-Subscription-And-Rg Succeeded"
	}

	$successcount = 0
	$vmlogincommands = New-Object "String[]" ($totalvmnumber+1)
	for($i=1; $i -le $totalvmnumber; $i++) {
		if($i -eq 1) { 
			$vmname=${vmnameprefix}
		} else {
			$vmname=${vmnameprefix}+"-"+${i}
		}

		Write-Host "Start creating VM: ${vmname}"

		Auto-Onboard-CGPU-Single-VM `
		-vmname $vmname

		$successcount=$successcount + 1

		Write-Host "Finished creating VM: ${vmname}"
	}

	Write-Host "******************************************************************************************"
	Write-Host "Please execute below commands to login to your VM(s):"
	for($i=1; $i -le $totalvmnumber; $i++) {
		Write-Host $vmlogincommands[$i]
	}
	Write-Host "Please execute the below command to try attestation:"
	Write-Host "cd cgpu-onboarding-package; sudo bash step-2-attestation.sh";
	Write-Host "Please execute the below command to try a sample workload:"
	Write-Host "sudo docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -v /home/${adminusername}/cgpu-onboarding-package:/home -it --rm nvcr.io/nvidia/tensorflow:24.03-tf2-py3 python /home/mnist-sample-workload.py";
	Write-Host "******************************************************************************************"

	Write-Host "Total VM to onboard: ${totalvmnumber}, total Success: ${successcount}."
	Write-Host "Detailed logs can be found at: .\logs\$logpath"
	
	az account clear
}

function Prepare-Subscription-And-Rg {
	Write-Host "Prepare subscription and resource group: ${subscriptionid}"
	if ( "$(az account show | Select-String $subscriptionid)" -eq "" )
	{
		Write-Host "Couldn't set to the correct subscription, please confirm and re-login with your azure account."

		az account clear
		az login
		az account set --subscription $subscriptionid

		if( "$(az account show | Select-String $subscriptionid)" -eq "")
		{
			Write-Host "The logged in azure account doesn't belongs to the subscription: ${subscription_id}. Please check subscriptionId or contact subscription owner to add your account."
			$global:issuccess = "failed"
			return
		}
	}

	Write-Host "SubscriptionId validation succeeded."
	Write-Host "Checking resource group...."
	if ($(az group exists --name $rg) -eq $false )
	{
		Write-Host "Resource group ${rg} does not exist, start creating resource group ${rg} in ${location} region"
		az group create --name ${rg} --location ${location}
		if ( $(az group exists --name $rg) -eq $false )
		{
			Write-Host "Resource group ${rg} creation failed, please check if your subscription is correct."
			$issuccess="failed"
			return
		}
		Write-Host "Resource group ${rg} creation succeeded."
	}

	Write-Host "Resource group ${rg} validation succeeded."
}

# Check that user has access to the direct share image 
function Check-Image-Access {
	Write-Host "Check image access for subscription: ${subscriptionid}"

	if( "$(az sig list-shared --location ${location} | Select-String "testGalleryDeirectShare")" -eq "")
	{
		Write-Host "Couldn't access direct share image from your subscription or tenant. Please make sure you have the necessary permissions."
		$global:issuccess = "failed"
		return
	}
}

# Auto Create and Onboard Single CGPU VM for customer.
function Auto-Onboard-CGPU-Single-VM {
	param($vmname)

	# Create VM
	$vmsshinfo=VM-Creation -rg $rg `
	 -location $location `
	 -publickeypath $publickeypath `
	 -vmname $vmname `
	 -adminusername $adminusername `
 	 -desid $desid
	if ($global:issuccess -eq "failed") {
		Write-Host "Failed to create VM."
		return
	}

	# Upload package to VM and extract it.
	Package-Upload -vmsshinfo $vmsshinfo `
	 -privatekeypath $privatekeypath `
	 -cgpupackagepath $cgpupackagepath `
	 -adminusername $adminusername
	if ($global:issuccess -eq "failed") {
		Write-Host "Failed to Package-Upload."
		return
	}

	# Update kernel
	Update-Kernel -vmsshinfo $vmsshinfo `
	 -privatekeypath $privatekeypath
	if ($global:issuccess -eq "failed") {
		Write-Host "Failed Update-Kernel."
		return
	}

	# Install GPU driver
	Install-GPU-Driver -vmsshinfo $vmsshinfo `
	 -privatekeypath $privatekeypath
	if ($global:issuccess -eq "failed") {
		Write-Host "Failed Install-GPU-Driver."
		return
	}

	# Attestation
	Attestation -vmsshinfo $vmsshinfo `
	 -privatekeypath $privatekeypath
	if ($global:issuccess -eq "failed") {
		Write-Host "Failed attestation."
		return
	}

	# Install gpu tools for execute sample workload.
	Install-GPU-Tools -vmsshinfo $vmsshinfo `
	 -privatekeypath $privatekeypath
	if ($global:issuccess -eq "failed") {
		Write-Host "Failed Install gpu tools."
		return
	}


	# Validation
	Validation -vmsshinfo $vmsshinfo `
	 -privatekeypath $privatekeypath
	if ($global:issuccess -eq "failed") {
		Write-Host "Failed validation."
		return
	}

	# Variables inherited from the calling function - could use $successcount instead of $i
	$vmlogincommands[$i] = "ssh -i ${privatekeypath} ${vmsshinfo}"

	return
}

# Create VM With given information.
function VM-Creation {
	param($rg,
		$location,
		$vmname,
		$adminusername,
		$publickeypath,
		$desid)

	$global:issuccess = "failed"

	$publickeypath="@${publickeypath}"
	$imageversion = "latest"

	# Check if VM name already exists within given resource group
	($exists = az vm show --resource-group $rg --name $vmname) 2>$null
	if([string]::IsNullOrEmpty($exists)) {
		if (!$desid) {
			Write-Host "Disk encryption set ID is not set, using Platform Managed Key for VM creation"
			$result=az vm create `
				--resource-group $rg `
				--name $vmname `
				--location $location `
				--image Canonical:0001-com-ubuntu-confidential-vm-jammy:22_04-lts-cvm:$imageversion `
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
		} else {
			Write-Host "Disk encryption set ID has been set, using Customer Managed Key for VM creation:"
			$result=az vm create `
				--resource-group $rg `
				--name $vmname `
				--location $location `
				--image Canonical:0001-com-ubuntu-confidential-vm-jammy:22_04-lts-cvm:$imageversion `
				--public-ip-sku Standard `
				--admin-username $adminusername `
				--ssh-key-values $publickeypath `
				--security-type ConfidentialVM `
				--os-disk-security-encryption-type DiskWithVMGuestState `
				--enable-secure-boot $true `
				--enable-vtpm $true `
				--size Standard_NCC40ads_H100_v5 `
				--os-disk-size-gb 100 `
				--os-disk-secure-vm-disk-encryption-set $desid `
				--verbose
		}

		# az vm fail or result being empty
		if ($? -eq $false -or [string]::IsNullOrEmpty($result)) {
			Write-Host "VM creation failed."
			return
		}

	} else {
		Write-Host "A virtual machine with the name $vmname already exists in $rg - please choose a unique name."
		return
	}

	Write-Host $result
	$resultjson = $result | ConvertFrom-Json
	$vmip= $resultjson.publicIpAddress
	$vmsshinfo=$adminusername+"@"+$vmip
	echo $vmsshinfo
	$global:issuccess = "succeeded"
	return
}

#Upload cgpu-onboarding-package.tar.gz to VM and extract it.
function Package-Upload {
	param($vmsshinfo,
		$adminusername,
		$privatekeypath,
		$cgpupackagepath)

	# Test VM connnection.
 	$isConnected=Try-Connect -vmsshinfo $vmsshinfo `
		-privatekeypath $privatekeypath

	if ($isConnected -eq $false) {
		Write-Host "VM connection failed after 50 retries."
		$global:issuccess = "failed"
		return
	}

	Write-Host "VM connection success."

	Write-Host "Starting Package-Upload."
	scp -i $privatekeypath $cgpupackagepath ${vmsshinfo}:/home/${adminusername}
	Write-Host "Finished Package-Upload."
	Write-Host "Starting extracting package."
	ssh -i ${privatekeypath} ${vmsshinfo} "tar -zxvf cgpu-onboarding-package.tar.gz;"
	Write-Host "Finished extracting package."
	$global:issuccess = "succeeded"
}

function Update-Kernel {
	param($vmsshinfo,
		$privatekeypath)

	# Test VM connnection.
 	$isConnected=Try-Connect -vmsshinfo $vmsshinfo `
		-privatekeypath $privatekeypath 

	if ($isConnected -eq $false) {
		Write-Host "VM connection failed after 50 retries."
		$global:issuccess = "failed"
		return
	} 
	Write-Host "VM connection success."

	Write-Host "Start update kernel"
	ssh  -i ${privatekeypath} ${vmsshinfo} "cd cgpu-onboarding-package; bash step-0-prepare-kernel.sh;"
	Write-Host "Finished update kernel."
	Write-Host "Rebooting..."

	$global:issuccess = "succeeded"
}

# Install Gpu driver.
function Install-GPU-Driver {
	param($vmsshinfo,
		$privatekeypath)

	# Test VM connnection.
 	$isConnected=Try-Connect -vmsshinfo $vmsshinfo `
		-privatekeypath $privatekeypath 

	if ($isConnected -eq $false) {
		Write-Host "VM connection failed after 50 retries."
		$global:issuccess = "failed"
		return
	} 
	Write-Host "VM connection success."

	Write-Host "Start GPU Driver install."
	ssh  -i ${privatekeypath} ${vmsshinfo} "cd cgpu-onboarding-package; bash step-1-install-gpu-driver.sh;"
	Write-Host "Finished install driver."
	$global:issuccess = "succeeded"
}

# Attestation GPU.
function Attestation {
	param($vmsshinfo,
		$privatekeypath)

	# Test VM connnection.
 	$isConnected=Try-Connect -vmsshinfo $vmsshinfo `
		-privatekeypath $privatekeypath

	if ($isConnected -eq $false) {
		Write-Host "VM connection failed after 50 retries."
		$global:issuccess = "failed"
		return
	}
	Write-Host "VM connection success."

	Write-Host "Start installing attestation package - this may take up to 5 minutes."
	echo $(ssh  -i ${privatekeypath} ${vmsshinfo} "cd cgpu-onboarding-package; echo Y | bash step-2-attestation.sh;") 2>&1 | Out-File -filepath ".\logs\$logpath\attestation.log"

	$attestationmessage=(Get-content -tail 20 .\logs\$logpath\attestation.log)
	echo $attestationmessage
	Write-Host "Finished attestation."
	$global:issuccess = "succeeded"
}

# Install GPU Tools
function Install-GPU-Tools {
	param($vmsshinfo,
		$privatekeypath)

	# Test VM connnection.
 	$isConnected=Try-Connect -vmsshinfo $vmsshinfo `
		-privatekeypath $privatekeypath 

	if ($isConnected -eq $false) {
		Write-Host "VM connection failed after 50 retries."
		$global:issuccess = "failed"
		return
	} 
	Write-Host "VM connection success."

	Write-Host "Start install gpu tools."
	ssh  -i ${privatekeypath} ${vmsshinfo} "cd cgpu-onboarding-package; echo Y | bash step-3-install-gpu-tools.sh;"
	Write-Host "Finish install gpu tools."
	$global:issuccess = "succeeded"
}


# Try to connect to VM with given SSH info with maximum retry of 50 times.
function Try-Connect {
	param($vmsshinfo,
		$privatekeypath)

	$connectionoutput="notconnected"
	$maxretrycount=50
	Write-Host "VM SSH info: ${vmsshinfo}"
	echo $vmsshinfo
	Write-Host "Private key path: ${privatekeypath}"
	echo $privatekeypath

	$currentRetry=0
	while ($connectionoutput -ne "connected" -and $currentRetry -lt $maxretrycount)
	{
		Write-Host "Trying to connect";
		$connectionoutput=ssh -i ${privatekeypath} -o "StrictHostKeyChecking no" ${vmsshinfo} "sudo echo 'connected'; "
		echo $connectionoutput
		if ($connectionoutput -eq "connected") {
			$global:issuccess = "succeeded"
			return
		}
		Start-sleep -Seconds 1
		$currentRetry++
	}
	$global:issuccess = "failed"
	return
}

function Validation {
	param($vmsshinfo,
			$privatekeypath)
	$global:issuccess = "succeeded"
	Write-Host "Started C-GPU capable validation."

	$securebootstate=$(ssh -i $privatekeypath $vmsshinfo "mokutil --sb-state;")
	if ($securebootstate -ne "SecureBoot enabled")
	{
		$global:issuccess="failed"
		Write-Host "Failed: secure boot state validation. Current secure boot state: ${securebootstate}"
	}
	else
	{
		Write-Host "Passed: secure boot state validation. Current secure boot state: ${securebootstate}"
	}

	$ccretrieve=$(ssh -i $privatekeypath $vmsshinfo "nvidia-smi conf-compute -f;")
	if ($ccretrieve -ne "CC status: ON")
	{
		$global:issuccess="failed"
		Write-Host "Failed: Confidential Compute retrieve validation. Current Confidential Compute retrieve state: ${ccretrieve}"
	}
	else 
	{
		Write-Host "Passed: Confidential Compute mode validation passed. Current Confidential Compute retrieve state: ${ccretrieve}"
	}

	$ccenvironment=$(ssh -i $privatekeypath $vmsshinfo "nvidia-smi conf-compute -e;")
	if ($ccenvironment -ne "CC Environment: PRODUCTION")
	{
		$global:issuccess="failed"
		Write-Host "Failed: Confidential Compute environment validation. Current Confidential Compute environment state: ${ccenvironment}"
	}
	else
	{
		Write-Host "Passed: Confidential Compute environment validation. Current Confidential Compute environment: ${ccenvironment}"
	}

	Write-Host "Finished C-GPU capable validation."
}
