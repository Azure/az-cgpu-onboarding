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
# required paramter:
# 	rg: name of your resource group. (please do az login to your subscription and create a resource group)
#	adminusername: your adminusername
#	publickeypath: your public key path
#	privatekeypath: your private key path
#	cgppackagepath: your cgpu-onboarding-pakcage.tar.gz path
#	vmnameprefix: the prefix of your vm. It will create from prefix1, prefix2, prefix3 till the number of retry specified;
#	totalvmnumber: the number of retry we want to perform.
#
# EG:
#Auto-Onboard-CGPU-Multi-VM `
#-tenantid "8af6653d-c9c0-4957-ab01-615c7212a40b" `
#-subscriptionid "9269f664-5a68-4aee-9498-40a701230eb2" `
#-rg "cgpu-test-rg" `
#-publickeypath "E:\cgpu\.ssh\id_rsa.pub" `
#-privatekeypath "E:\cgpu\.ssh\id_rsa"  `
#-cgpupackagepath "E:\cgpu\cgpu-onboarding-package.tar.gz" `
#-adminusername "admin" `
#-serviceprincipalid "4082afe7-2bca-4f09-8cd1-a584c0520588" `
#-serviceprincipalsecret "FBw8..." `
#-vmnameprefix "cgpu-test" `
#-totalvmnumber 2

# Auto Create and Onboard Multiple CGPU VM for customer.
function Auto-Onboard-CGPU-Multi-VM {
	param(
		$tenantid,
		$subscriptionid,
		$rg,
		$publickeypath,
		$privatekeypath,
		$cgpupackagepath,
		$adminusername,
		$serviceprincipalid,
		$serviceprincipalsecret,
		$vmnameprefix,
		$totalvmnumber)



	if (!(Test-Path ".\logs\"))
	{
		New-Item -ItemType Directory -Force -Path ".\logs\"
		Write-Host "Created log file directory"
	}

	if ( "$(az --version | Select-String 'azure-cli')" -eq "" ) {
        	echo "Azure CLI is not installed, please try install Azure CLI first: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?tabs=powershell"
        	echo "Note: you might need to restart powershell after install."
        return
    	}

	echo "Tenant id: ${tenantid}"
	echo "Subscription id: ${subscriptionid}"
	echo "Resource group: ${rg}"

	echo "Public key path:  ${publickeypath}"
	if (-not(Test-Path -Path $publickeypath -PathType Leaf)) {
		echo "${public_key_path} does not exist, please verify file path"
    	return
	}

	echo "Private key path:  ${privatekeypath}"
	if (-not(Test-Path -Path $privatekeypath -PathType Leaf)) {
		echo "${privatekeypath} does not exist, please verify file path"
    	return
	}

	echo "Cgpu onboarding package path:  ${cgpupackagepath}"
	if (-not(Test-Path -Path $cgpupackagepath -PathType Leaf)) {
		echo "${privatekeypath} does not exist, please verify file path"
    	return
	}

	echo "Admin user name:  ${adminusername}"
	echo "Service principal id:  ${serviceprincipalid}"
	echo "Service principal secret:  Hidden"
	echo "Vm Name prefix:  ${vmnameprefix}"
	echo "Total VM number:  ${totalvmnumber}"
	echo ""

	echo "Clear previous account info."
	
	az account clear
	az login --tenant $tenantid 2>&1 | Out-File -filepath ".\logs\login-operation.log"
	az account set --subscription $subscriptionid
	az account show

	$global:issuccess = "succeeded"
	Prepare-Subscription-And-Rg
	if ($global:issuccess -eq "failed") {
		echo "Failed to Prepare-Subscription-And-Rg.."
		return
	}

	Prepare-Access-Token
	
	if ($global:issuccess -eq "failed") {
		echo "Failed to Prepare-Access-Token.."
		return
	}

	$successcount = 0
	$vmlogincommands = New-Object "String[]" ($totalvmnumber+1)
	for($i=1; $i -le $totalvmnumber; $i++) {
		$vmname=${vmnameprefix}+"-"+${i}

		echo "Start creating VM: '${vmname}'"

		Auto-Onboard-CGPU-Single-VM `
		-vmname $vmname

		$successcount=$successcount + 1

		echo "Finished creating VM: '${vmname}'"
	}
	echo "******************************************************************************************"
	echo "Please execute below commands to login to your VM(s):"
	for($i=1; $i -le $totalvmnumber; $i++) {
		echo $vmlogincommands[$i]
	}
	echo "Please execute the below command to try attestation:"
	echo "cd cgpu-onboarding-package; bash step-2-attestation.sh";
	echo "Please execute the below command to try a sample workload:"
	echo "cd; bash mnist_example.sh pytorch";
	echo "******************************************************************************************"

	echo "Total VM to onboard: ${totalvmnumber}, total Success: ${successcount}."

	az account clear
	echo "------------------------------------------------------------------------------------------"
	echo "# Optional: Clean up Contributor Role in your ResourceGroup."
	echo "# az login --tenant ${tenant_id}"
	echo "# az role assignment delete --assignee ${serviceprincipalid} --role \"Contributor\" --resource-group ${rg}"
}

function Prepare-Subscription-And-Rg {
	echo "Prepare subscription and resource group: ${subscriptionid}"
	if ( "$(az account show | Select-String $subscriptionid)" -eq "" )
	{
		echo "Couldn't set to the correct subscription, please confirm and re-login with your azure account."

		az account clear 2>&1 | Out-File -filepath ".\logs\login-operation.log"
		az login
		az account set --subscription $subscriptionid 2>&1 | Out-File -filepath ".\logs\login-operation.log"

		if( "$(az account show | Select-String $subscriptionid)" -eq "")
		{
			echo "The logged in azure account doesn't belongs to the subscription: ${subscription_id}. Please check subscriptionId or contact subscription owner to add your account."
			$global:issuccess = "failed"
			return
		}
	}

	echo "SubscriptionId validation succeeded."
	echo "Checking resource group...."
	if ($(az group exists --name $rg) -eq $false )
	{
    	echo "Resource group ${rg} does not exist, start creating resource group ${rg}"
    	az group create --name ${rg} --location eastus2 2>&1 | Out-File -filepath ".\logs\login-operation.log" 
		if ( $(az group exists --name $rg) -eq $false )
		{
			echo "rg creation failed, please check if your subscription is correct."
			$issuccess="failed"
			return
		}
		echo "Resource group ${rg} creation succeeded."
	}

	echo "Resource group ${rg} validation succeeded."
}

function Prepare-Access-Token {
	echo "Prepare access token. ${subscriptionid}"

	# check contributor role for service principal
	if ( "$(az role assignment list --assignee $serviceprincipalid --resource-group $rg --role "Contributor" | Select-String "Contributor")" -eq "" )
	{
		echo "Contributor role doesn't exist for resource group ${rg}."
		echo "Start creating Contributor role in target resource group ${rg} for service principal ${serviceprincipalid}."

		# assign contributor role for service principal
		echo "Assign service pricipal Contributor role."
		az role assignment create --assignee $serviceprincipalid --role "Contributor" --resource-group $rg 2>&1 | Out-File -filepath ".\logs\prepare-token.log"

	} else {
		echo "Service principal ${serviceprincipalid} contributor role has already been provisioned to target ${rg}"

	}

	if("$(az role assignment list --assignee $serviceprincipalid --resource-group $rg --role "Contributor" | Select-String "Contributor")" -eq "") {
		echo "Create and Validate Contributor role failed in resource group: ${rg}."
		$global:issuccess="failed"
	}

	# get access token for image in Microsoft tenant.
	az account clear 2>&1 | Out-File -filepath ".\logs\prepare-token.log"
	az login --service-principal -u $serviceprincipalid -p $serviceprincipalsecret --tenant "72f988bf-86f1-41af-91ab-2d7cd011db47" 2>&1 | Out-File -filepath ".\logs\prepare-token.log"
	az account get-access-token

	# get access token for customer's resource group.
	az login --service-principal -u $serviceprincipalid -p $serviceprincipalsecret --tenant $tenantid 2>&1 | Out-File -filepath ".\logs\prepare-token.log"
	az account get-access-token 2>&1 | Out-File -filepath ".\logs\prepare-token.log"
}

# Auto Create and Onboard Single CGPU VM for customer.
function Auto-Onboard-CGPU-Single-VM{
	param(
		$vmname)

	# Create VM
 	$vmsshinfo=VM-Creation -rg $rg `
 	 -publickeypath $publickeypath `
 	 -vmname $vmname `
 	 -adminusername $adminusername

	# Upload package to VM and extract it.
	Package-Upload -vmsshinfo $vmsshinfo `
	 -privatekeypath $privatekeypath `
	 -cgpupackagepath $cgpupackagepath `
	 -adminusername $adminusername
	if ($global:issuccess -eq "failed") {
		echo "Failed to Package-Upload.."
		return
	}

	# Attestation
	Attestation -vmsshinfo $vmsshinfo `
	 -privatekeypath $privatekeypath
	if ($global:issuccess -eq "failed") {
		echo "Failed attestation.."
		return
	} 
	else
	{
		echo "Passed attestation"
	}

	# Validation
	Validation -vmsshinfo $vmsshinfo `
	 -privatekeypath $privatekeypath
	if ($global:issuccess -eq "failed") {
		echo "Failed validation.."
		return
	}

	# Variables inherited from the calling function - could use $successcount instead of $i
	$vmlogincommands[$i] = "ssh -i ${privatekeypath} ${vmsshinfo}"

	return
}

# Create VM With given information.
function VM-Creation {
	param($rg,
		$vmname,
		$adminusername,
		$publickeypath)
		
	echo "Please wait, creating the VM can take up to 10 minutes."

	$publickeypath="@${publickeypath}"
	$result=az vm create `
		--resource-group $rg `
		--name $vmname `
	    --image "/subscriptions/85c61f94-8912-4e82-900e-6ab44de9bdf8/resourceGroups/cgpu-image-gallary/providers/Microsoft.Compute/galleries/cgpunvidiaimagegallery/images/cgpunvidiaimage/versions/0.0.1" `
		--public-ip-sku Standard `
		--admin-username $adminusername `
		--ssh-key-values $publickeypath `
		--security-type "TrustedLaunch" `
		--enable-secure-boot $true `
		--enable-vtpm $true `
		--size Standard_NCC24ads_A100_v4 `
		--os-disk-size-gb 100 `
		--verbose

	$resultjson = $result | ConvertFrom-Json
	$vmip= $resultjson.publicIpAddress
	$vmsshinfo=$adminusername+"@"+$vmip
	echo $vmsshinfo
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
		echo "VM connection failed after 50 times retry."
		$global:issuccess = "failed"
		return
	}

	echo "VM connection success."

	echo "Start Package-Upload."
	scp -i $privatekeypath $cgpupackagepath ${vmsshinfo}:/home/${adminusername}
	echo "Finished Package-Upload."
	echo "start extract."
	ssh -i ${privatekeypath} ${vmsshinfo} "tar -zxvf cgpu-onboarding-package.tar.gz;"
	echo "finish extract."
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
		echo "VM connection failed after 50 times retry."
		$global:issuccess = "failed"
		return
	}
	echo "VM connection success."

	echo "Starting attestation process. Please wait, this may take up to 2 minutes."
	echo $(ssh  -i ${privatekeypath} ${vmsshinfo} "cd cgpu-onboarding-package; echo Y | bash step-2-attestation.sh;") 2>&1 | Out-File -filepath ".\logs\attestation.log"
	$attestationmessage=(Get-content -tail 20 .\logs\attestation.log)
	echo $attestationmessage
	echo "Finished attestation."
	$global:issuccess = "succeeded"
}


# Try to connect to VM with Given ssh info with maximum retry of 50 times.
function Try-Connect {
	param($vmsshinfo,
		$privatekeypath)

	$connectionoutput="notconnected"
	$maxretrycount=50
	echo "vmsshinfo in try connect"
	echo $vmsshinfo
	echo "private key path in try connect"
	echo $privatekeypath

	$currentRetry=0
	while ($connectionoutput -ne "connected" -and $currentRetry -lt $maxretrycount)
	{
		echo "try to connect:";
		$connectionoutput=ssh -i ${privatekeypath} -o "StrictHostKeyChecking no" ${vmsshinfo} "sudo echo 'connected'; "
		echo $connectionoutput
		if ($connectionoutput -eq "connected") {
			$global:issuccess = "succeeded"
			return
		}

		$currentRetry++
	}
	$global:issuccess = "failed"
	return
}

function Validation {
	param($vmsshinfo,
		  $privatekeypath)
	$global:issuccess = "succeeded"
	echo "Started cgpu capable validation."
	$kernelversion=$(ssh -i $privatekeypath $vmsshinfo "sudo uname -r;")
	if ($kernelversion -ne "5.15.0-1019-azure")
	{
		$global:issuccess="failed"
		echo "Failed: kernel version validation. Current kernel: ${kernelversion}"
	}
	else
	{
		echo "Passed: kernel validation. Current kernel: ${kernelversion}"
	}

	$securebootstate=$(ssh -i $privatekeypath $vmsshinfo "mokutil --sb-state;")
	if ($securebootstate -ne "SecureBoot enabled")
	{
		$global:issuccess="failed"
		echo "Failed: secure boot state validation. Current secure boot state: ${securebootstate}"
	}
	else
	{
		echo "Passed: secure boot state validation. Current secure boot state: ${securebootstate}"
	}

	$ccretrieve=$(ssh -i $privatekeypath $vmsshinfo "nvidia-smi conf-compute -f;")
	if ($ccretrieve -ne "CC status: ON")
	{
		$global:issuccess="failed"
		echo "Failed: Confidential Compute retrieve validation. Current Confidential Compute retrieve state: ${ccretrieve}"
	}
	else
	{
		echo "Passed: Confidential Compute mode validation passed. Current Confidential Compute retrieve state: ${ccretrieve}"
	}

	$ccenvironment=$(ssh -i $privatekeypath $vmsshinfo "nvidia-smi conf-compute -e;")
	if ($ccenvironment -ne "CC Environment: INTERNAL")
	{
		$global:issuccess="failed"
		echo "Failed: Confidential Compute environment validation. Current Confidential Compute environment state: ${ccenvironment}"
	}
	else
	{
		echo "Passed: Confidential Compute environment validation. Current Confidential Compute environment: ${ccenvironment}"
	}

	$attestationresult=$(ssh -i $privatekeypath $vmsshinfo "cd cgpu-onboarding-package; bash step-2-attestation.sh | tail -1| sed -e 's/^[[:space:]]*//'")
	if ($attestationresult -ne "GPU 0 verified successfully.")
	{
		$global:issuccess="failed"
		echo "Failed: Attestation validation failed. Last attestation message: ${attestationresult}"
	}
	else
	{
		echo "Passed: Attestation validation passed. Last attestation message: ${attestationresult}"
	}

	echo "Finished cgpu capable validation."
}
