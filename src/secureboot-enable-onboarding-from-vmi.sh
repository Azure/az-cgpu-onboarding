# This script will help to get you authenticated with Microsoft tenant 
# and get access to a private Canonical-signed confidential GPU-capable image with an Nvidia GPU driver already installed.
# Then it will launch VMs with secure boot enabled, based on the provided arguments in your specified resource group.
#
# Note: First time execution will require the administrator role for the target Azure subscription to
# provision by generating the associated service principal contributor roles in your target resource group. 
#
# Required Arguments: 
#	-t <tenant ID>: ID of your Tenant/Directory
#	-s <subscription ID>: ID of your subscription.
#	-r <resource group name>: The resource group name for VM creation
#                          It will create the Resource Group if it is not found under given subscription
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
# -c "/home/username/cgpu-onboarding-package.tar.gz" \
# -a "azuretestuser" \
# -d "4082afe7-2bca-4f09-8cd1-a584c0520589" \
# -x "FBw8......." \
# -v "confidential-test-vm"  \
# -n 1

# Auto Create and Onboard Multiple CGPU VM with Nvidia Driver pre-installed image. 
auto_onboard_cgpu_multi_vm() {
	while getopts t:s:r:p:i:c:a:v:d:x:n: flag
	do
	    case "${flag}" in
			t) tenant_id=${OPTARG};;
			s) subscription_id=${OPTARG};;
	        r) rg=${OPTARG};;
	        p) public_key_path=${OPTARG};;
	        i) private_key_path=${OPTARG};;
	        c) cgpu_package_path=${OPTARG};;
	        a) adminuser_name=${OPTARG};;
	        d) service_principal_id=${OPTARG};;
	        x) service_principal_secret=${OPTARG};;
	        v) vmname_prefix=${OPTARG};;
	        n) total_vm_number=${OPTARG};;
	    esac
	done

	echo "Tenant id: ${tenant_id}" 
	echo "subscription id: ${subscription_id}" 
	echo "Resource group: ${rg}" 
	echo "Public key path:  ${public_key_path}"
	echo "Private key path:  ${private_key_path}"
	echo "Cgpu onboarding package path:  ${cgpu_package_path}"
	echo "Admin user name:  ${adminuser_name}"
	echo "Service principal id:  ${service_principal_id}"
	echo "Service principal secret:  Hidden"
	echo "Vm Name prefix:  ${vmname_prefix}"
	echo "Total VM number:  ${total_vm_number}"
	echo ""

	echo "Clear previous account info."
	az account clear
	az login --tenant ${tenant_id}
	az account set --subscription $subscription_id

	prepare_subscription_and_rg
	if [ "$is_success" == "failed" ]; then
		echo "failed to prepare_subscription_and_rg.."
		return
	fi

	prepare_access_token 2>&1 | tee -a logs/current-operation.log
	
	if [ "$is_success" == "more_action_need" ]; then
		echo "Please retry secureboot-enable-onboarding-from-vmi.sh after finishing above steps."
		return
	fi

	if [ "$is_success" == "failed" ]; then
		echo "failed to prepare_access_token.."
		return
	fi
	# start Vm creation with number of specified VMs.
	current_vm_count=1
	successCount=0
	while [ $current_vm_count -le $total_vm_number ]
	do
		is_success="Succeeded"
		if [ $current_vm_count == 1 ];
		then 
			vmname="${vmname_prefix}";
		else 
			vmname_ending=$(($current_vm_count+1));
			vmname="${vmname_prefix}-${vmname_ending}"
		fi

		echo "vmname: ${vmname}";
		auto_onboard_cgpu_single_vm $vmname
		validation
		if [ "$is_success" == "Succeeded" ];
		then 
			successCount=$(($successCount+1))
		fi
		echo "Current number of VM finished: ${current_vm_count}, total Success: ${successCount}."
		current_vm_count=$(($current_vm_count + 1))
	done

	echo "Total VM to onboard: ${total_vm_number}, total Success: ${successCount}."

	az account clear
	echo "------------------------------------------------------------------------------------------"
	echo "# Optional: Clean up Contributor Role in your ResourceGroup."
	echo "# az login --tenant ${tenant_id}"
	echo "# az role assignment delete --assignee ${service_principal_id} --role \"Contributor\" --resource-group ${rg}"
}

# login to subscription and check resource group. 
# It will create an resource group if it doesn't exist.
prepare_subscription_and_rg() {
	if [ "$(az account show | grep $subscription_id)" == "" ]; then
		echo "Couldn't set to the correct subscription, please confirm and re-login with your azure account."
		az account clear
		az login
		az account set --subscription $subscription_id

		if [ "$(az account show | grep $subscription_id)" == "" ]; then
			echo "the logged in azure account doesn't belong to subscription: ${subscription_id}. Please check subscriptionId or contact subscription owner to add your account."	
			is_success="failed"
			return
		fi 
		
	fi 
	
	echo "SubscriptionId validation success."
	echo "Checking resource group...."
	if [ $(az group exists --name $rg) == false ]; then
    	echo "Resource group ${rg} does not exits, start creating resource group ${rg}"
    	az group create --name ${rg} --location eastus2
		if [ $(az group exists --name $rg) == false ]; then
			echo "rg creation failed, please check if your subscription is correct."
			is_success="failed"
			return
		fi
		echo "Resource group ${rg} create success."
	fi

	echo "Resource group ${rg} validation Succeeded."
}

prepare_access_token() {
	# check if service prinicipal has been provisioned to customer's tenant.
	if [ "$(az ad sp list  --display-name "cgpu" | grep $service_principal_id)" == "" ]; then 
		echo "Can not find service principal: ${service_principal_id} in tenant: ${tenant_id}."
		echo "First time access Confidential Compute GPU Image needs to provision ${service_principal_id} to tenant: ${tenant_id}. "

		echo "Please try below URL to import service principal and then retry the operation."
		echo "------------------------------------------------------------------------------------------"
		echo "https://login.microsoftonline.com/${tenant_id}/oauth2/authorize?client_id=${service_principal_id}&response_type=code&redirect_uri=https%3A%2F%2Fwww.microsoft.com%2F"
		echo "------------------------------------------------------------------------------------------"

		is_success="more_action_need"
		return
	fi

	echo "Validated Service prinicipal ${service_principal_id} has already been provisioned into ${tenant_id} "

	# check contributor role for service principal
	if [ "$(az role assignment list --assignee $service_principal_id --resource-group $rg --role "Contributor" | grep "Contributor")" == "" ]; then
		echo "Contributor role doesn't exist for resource group ${rg}."	
		echo "Start creating Contributor role in target resource group ${rg} for service principal ${service_principal_id}."	
		
		# assign contributor role for service pricipal
		echo "Assign service principal Contributor role."
		az role assignment create --assignee $service_principal_id --role "Contributor" --resource-group $rg
	else 
		echo "Service principal ${service_principal_id} contributor role has already been provisioned to target ${rg}"
	fi 

	if [ "$(az role assignment list --assignee $service_principal_id --resource-group $rg --role "Contributor" | grep "Contributor")" == "" ]; then
		echo "Create and Validate Contributor role failed in resource group: ${rg}."
		is_success="failed"
		return
	fi

	# get access token for image in Microsoft tenant.
	az account clear
	az login --service-principal -u $service_principal_id -p $service_principal_secret --tenant "72f988bf-86f1-41af-91ab-2d7cd011db47"
	if [ "$(az account get-access-token | grep "Bearer")" == "" ]; then
		echo "Failed to get token from microsoft tenant. Please make sure the service principal id and service principal secret are correct."
		echo "If it continues to fail, please contact Microsoft CGPU team for more information."
		is_success="failed"
		return
	fi

	# get access token for customer's resource group.
	az login --service-principal -u $service_principal_id -p $service_principal_secret --tenant $tenant_id
	if [ "$(az account get-access-token | grep "Bearer")" == "" ]; then
		echo "Failed to get token from microsoft tenant. Please make sure the service principal id and service principal secret are correct."
		echo "If it continues to fail, please contact Microsoft CGPU team for more information."
		is_success="failed"
		return
	fi
	
	echo "Get access token success."
}

# Create a single VM and onboard confidential gpu.
auto_onboard_cgpu_single_vm() {
	local vmname=$1
	create_vm $vmname
	ip=$(az vm show -d -g $rg -n $vmname --query publicIps -o tsv)
	vm_ssh_info=$adminuser_name@$ip
	
	echo "VM creation finished"
	echo $vm_ssh_info

	# Upload customer onboarding package.
	upload_package
	
	# Attestation.
	attestation

	echo "******************************************************************************************"
	echo "Please execute below command to login to your VM and try attestation:"
	echo "ssh -i $private_key_path $vm_ssh_info" 
	echo "cd cgpu-onboarding-package; bash step-2-attestation.sh";
	echo "------------------------------------------------------------------------------------------"
	echo "Please execute below command to login to your VM and try a sample workload:"
	echo "ssh -i $private_key_path $vm_ssh_info" 
	echo "bash mnist_example.sh pytorch";
	echo "******************************************************************************************"
}

# Upload_package to VM.
upload_package() {
	echo "start upload package..."
	try_connect
	scp -i $private_key_path $cgpu_package_path $vm_ssh_info:/home/$adminuser_name

	echo "start extract package..."
	ssh -i $private_key_path $vm_ssh_info "tar -zxvf cgpu-onboarding-package.tar.gz;"
}

# Do attestation in the created VMs.
attestation() {
	echo "start attestation..."
	try_connect
	ssh -i $private_key_path $vm_ssh_info "cd cgpu-onboarding-package; echo Y | bash step-2-attestation.sh;"

}

# Try to connect to VM with 50 maximum retry.
try_connect() {
	#echo "start try connect"
	connectionoutput="disconnected"
	while [ "$connectionoutput" != "connected" ];
	do
		#echo "try to connect:"
		connectionoutput=$(ssh -i $private_key_path -o "StrictHostKeyChecking no" $vm_ssh_info "sudo echo 'connected';")
		echo $connectionoutput
	done
}

# Create a single VM.
create_vm() {
	local vmname=$1
	echo "start creating VM: '${vmname}'"

	public_key_path_with_at="@$public_key_path"
	
	az vm create \
	--resource-group $rg \
	--name $vmname \
	--image "/subscriptions/85c61f94-8912-4e82-900e-6ab44de9bdf8/resourceGroups/cgpu-image-gallary/providers/Microsoft.Compute/galleries/cgpunvidiaimagegallery/images/cgpunvidiaimage/versions/0.0.1" \
	--public-ip-sku Standard \
	--admin-username $adminuser_name \
	--ssh-key-values $public_key_path_with_at \
	--security-type "TrustedLaunch" \
	--enable-secure-boot true \
	--enable-vtpm true \
	--size Standard_NCC24ads_A100_v4 \
	--os-disk-size-gb 100 \
	--verbose
}

validation() {
	echo "Validate Confidential GPU capability."	
	try_connect
	kernel_version=$(ssh -i $private_key_path $vm_ssh_info "sudo uname -r;")
	
	if [ "$kernel_version" != "5.15.0-1019-azure" ];
	then
		is_success="failed"
		echo "Failed: kernel version validation. Current kernel: ${kernel_version}"
	else
		echo "Passed: kernel validation. Current kernel: ${kernel_version}"
	fi

	secure_boot_state=$(ssh -i $private_key_path $vm_ssh_info "mokutil --sb-state;")
	if [ "$secure_boot_state" != "SecureBoot enabled" ];
	then
		is_success="failed"
		echo "Failed: secure boot state validation. Current secure boot state: ${secure_boot_state}"
	else
		echo "Passed: secure boot state validation. Current secure boot state: ${secure_boot_state}"
	fi

	cc_retrieve=$(ssh -i $private_key_path $vm_ssh_info "nvidia-smi conf-compute -f;")
	if [ "$cc_retrieve" != "CC status: ON" ];
	then
		is_success="failed"
		echo "Failed: Confidential Compute retrieve validation. current Confidential Compute retrieve is ${cc_retrieve}"
	else 
		echo "Passed: Confidential Compute mode validation passed. Current Confidential Compute retrieve is ${cc_retrieve}"
	fi

	cc_environment=$(ssh -i $private_key_path $vm_ssh_info "nvidia-smi conf-compute -e;")
	if [ "$cc_environment" != "CC Environment: INTERNAL" ];
	then
		is_success="failed"
		echo "Failed: Confidential Compute environment validation. current Confidential Compute environment is ${cc_environment}"
	else 
		echo "Passed: Confidential Compute environment validation. current Confidential Compute environment is ${cc_environment}"

	fi

	attestation_result=$(ssh -i $private_key_path $vm_ssh_info "cd cgpu-onboarding-package; bash step-2-attestation.sh | tail -1| sed -e 's/^[[:space:]]*//'")
	if [ "$attestation_result" != "GPU 0 verified successfully." ];
	then
		is_success="failed"
		echo "Failed: Attestation validation failed. last attestation message: ${attestation_result}"
	else 
		echo "Passed: Attestation validation passed. last attestation message: ${attestation_result}"
	fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ];
    then
        mkdir logs
    fi

    auto_onboard_cgpu_multi_vm "$@"
fi
