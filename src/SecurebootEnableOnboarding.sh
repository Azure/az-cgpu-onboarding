# This Scripts will help to get authenticated with microsoft tenant 
# and get access to a private Cononical Signed Confidential Gpu capable Image with Nvidia GPU driver installed.
# Then it will lanucn SecureBoot Enabled VMs based on provided argument in specified resource group.
#
# Note: First time execution will required administrator role for the target Azure subsciption to
# provision generate associate serviceprincipal contributor roles in target resource group. 
#
# Required Arguments: 
#	-t <tenant id>: Id of your Tenant/Directory. 
#	-s <subscription id>: Id of your subscription. 
#	-r <resource group name>: The resource group name for Vm creation.
#                          It will create ResourceGroup if it is not found under given subscription.
#	-p <public key path>: your id_rsa.pub path. 
#	-i <private key path>: your id_rsa path. 
#	-c <CustomerOnboardingPackage path>: Customer onboarding package path.
#	-a <admin user name>: Admin user name.
#	-s <service principal id>: your service principal id you got from microsoft.
#	-x <secret>: your service principal secrect you got from microsoft.
#	-v <vm name>: your VM name
#	-n <vm number>: number of vm to be generated.
#
# Example:
# bash SecurebootEnableOnboarding.sh  \
# -t "8af6653d-c9c0-4957-ab01-615c7212a40b" \
# -s "9269f664-5a68-4aee-9498-40a701230eb2" \
# -r "confidential-gpu-rg" \
# -p "/home/username/.ssh/id_rsa.pub"  \
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

	echo "clear previous acocunt info."
	az account clear
	az login
	echo "Tenant id: ${tenant_id}" 
	echo "Resource group: ${rg}" 
	echo "Public key path:  ${public_key_path}"
	echo "Private key path:  ${private_key_path}"
	echo "Cgpu onboarding package path:  ${cgpu_package_path}"
	echo "Admin user name:  ${adminuser_name}"
	echo "Service principal id:  ${service_principal_id}"
	echo "Service principal secret:  Hided"
	echo "Vm Name prefix:  ${vmname_prefix}"
	echo "Total VM number:  ${total_vm_number}"

	prepare_subscription_and_rg
	if [ "$is_success" == "failed" ]; then
		echo "failed to prepare_subscription_and_rg.."
		return
	fi

	prepare_access_token
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
		vmname="${vmname_prefix}-${current_vm_count}"
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
	echo "# Optional: clean up Contributor Role in customer's ResourceGroup."
	echo "# az login"
	echo "# az role assignment delete --assignee ${service_principal_id} --role \"Contributor\" --resource-group ${rg}"
}

# login to subscription and check resource group. 
# It will create an resource group if it doesn't exist.
prepare_subscription_and_rg() {
	if [ "$(az account show | grep $subscription_id)" == "" ]; then
		az login
		az account set --subscription $subscription_id

		if [ "$(az account show | grep $subscription_id)" == "" ]; then
			echo "the logged in azure account don't belongs to subsciprtion: ${subscription_id}. Please check subscriptionId or contact subscription owner to add your account."	
			is_success="failed"
			return
		fi 
		
	fi 
	
	echo "SubscriptionId validation success."
	echo "Checking reource group...."
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
	# check contributor role for service principal
	if [ "$(az role assignment list --assignee $service_principal_id --resource-group $rg --role "Contributor" | grep "Contributor")" == "" ]; then
		echo "Contributor role dosen't exist for resource group ${rg}."	
		echo "Start creating Contributor role in target resource group ${rg} for service principal ${service_principal_id}."	
		
		# assign contributor role for service pricipal
		echo "Assign service pricipal Contributor role."
		az role assignment create --assignee $service_principal_id --role "Contributor" --resource-group $rg
	else 
		echo "Service principal ${service_principal_id} contributor role has already been provisioned to target ${rg}"
	fi 

	if [ "$(az role assignment list --assignee $service_principal_id --resource-group $rg --role "Contributor" | grep "Contributor")" == "" ]; then
		echo "Create and Validate Contributor role failed in resource group: ${rg}."
		is_success="failed"
	fi

	# get access token for image in Microsoft tenant.
	az account clear
	az login --service-principal -u $service_principal_id -p $service_principal_secret --tenant "72f988bf-86f1-41af-91ab-2d7cd011db47"
	az account get-access-token 

	# get access token for customer's resource group.
	az login --service-principal -u $service_principal_id -p $service_principal_secret --tenant $tenant_id
	az account get-access-token 
}

# Create a single VM and onboard confidential gpu.
auto_onboard_cgpu_single_vm() {
	local vmname=$1
	create_vm $vmname
	ip=$(az vm show -d -g $rg -n $vmname --query publicIps -o tsv)
	vm_ssh_info=$adminuser_name@$ip
	
	echo "vm creation finished"
	echo $vm_ssh_info

	# Upload customer onboarding package.
	upload_pacakge
	
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
upload_pacakge() {
	echo "start upload pacakge..."
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
	echo "start try connect"
	connectionoutput="disconnected"
	while [ "$connectionoutput" != "connected" ];
	do
		echo "try to connect:"
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
	--image "/subscriptions/85c61f94-8912-4e82-900e-6ab44de9bdf8/resourceGroups/cgpu-image-gallary/providers/Microsoft.Compute/galleries/cgpuimagegallary/images/xiaobotestimage/versions/0.0.3" \
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
		echo "kernel version validation failed. current kernel is ${kernel_version}"
	else
		echo "kernel validation passed. Current kernel: ${kernel_version}"
	fi

	secure_boot_state=$(ssh -i $private_key_path $vm_ssh_info "mokutil --sb-state;")
	
	if [ "$secure_boot_state" != "SecureBoot enabled" ];
	then
		is_success="failed"
		echo "secure boot state validation failed. current kernel is ${secure_boot_state}"
	else
		echo "secure boot state validation passed. Current kernel: ${secure_boot_state}"
	fi

	cc_retrieve=$(ssh -i $private_key_path $vm_ssh_info "nvidia-smi conf-compute -f;")
	echo $cc_retrieve
	if [ "$cc_retrieve" != "CC status: ON" ];
	then
		is_success="failed"
		echo "Confidential Compute retrieve validation failed. current Confidential Compute retrieve is ${cc_retrieve}"
	else 
		echo "Confidential Compute mode validation passed. Current Confidential Compute retrieve is ${cc_retrieve}"
	fi

	cc_environment=$(ssh -i $private_key_path $vm_ssh_info "nvidia-smi conf-compute -e;")
	if [ "$cc_environment" != "CC Environment: INTERNAL" ];
	then
		is_success="failed"
		echo "Confidential Compute environment validation failed. current Confidential Compute environment is ${cc_environment}"
	else 
		echo "Confidential Compute environment validation passed. current Confidential Compute environment is ${cc_environment}"

	fi

	attestation_result=$(ssh -i $private_key_path $vm_ssh_info "cd cgpu-onboarding-package; bash step-2-attestation.sh | tail -1| sed -e 's/^[[:space:]]*//'")
	if [ "$attestation_result" != "GPU 0 verified successfully." ];
	then
		is_success="failed"
		echo "Attestation validation failed. last attestation message: ${attestation_result}"
	else 
		echo "Attestation validation passed. last attestation message: ${attestation_result}"
	fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    auto_onboard_cgpu_multi_vm "$@"
fi