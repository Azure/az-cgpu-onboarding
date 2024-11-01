# This script will help to get you get access to a private Canonical-signed confidential GPU-capable image with an Nvidia GPU driver already installed.
# Then it will launch VMs with secure boot enabled, based on the provided arguments in your specified resource group.
#
#
# Required Arguments: 
#	-t <tenant ID>: ID of your Tenant/Directory
#	-s <subscription ID>: ID of your subscription.
#	-r <resource group name>: The resource group name for VM creation
#                          It will create the Resource Group if it is not found under given subscription
#	-p <public key path>: your id_rsa.pub path 
#	-i <private key path>: your id_rsa path
#   -d <disk encryption id>: customer managed disk encryption id
#	-c <CustomerOnboardingPackage path>: Customer onboarding package path
#	-a <admin user name>: administrator username for the VM
#	-v <vm name>: your VM name
#	-n <vm number>: number of VMs to be generated
#
# Optional Arguments:
#    -l <region>: the location of your resources (if not specified, the default is eastus2)
#    -o <OS disk size>: the size of your OS disk (if not specified, the default is 100 GB)
#    -e <encryption type>: the type of CVM encryption for your OS disk (if not specified, the default is DiskWithVMGuestState)
# 
# Example:
# bash secureboot-enable-onboarding-from-vmi.sh  \
# -t "8af6653d-c9c0-4957-ab01-615c7212a40b" \
# -s "9269f664-5a68-4aee-9498-40a701230eb2" \
# -r "confidential-gpu-rg" \
# -l "eastus2" \
# -p "/home/username/.ssh/id_rsa.pub" \
# -i "/home/username/.ssh/id_rsa"  \
# -d "/subscriptions/85c61f94-8912-4e82-900e-6ab44de9bdf8/resourceGroups/CGPU-CMK-KV/providers/Microsoft.Compute/diskEncryptionSets/CMK-Test-Des-03-01"  \
# -c "/home/username/cgpu-onboarding-package.tar.gz" \
# -a "azuretestuser" \
# -v "confidential-test-vm"  \
# -o 100 \
# -n 1

# Auto Create and Onboard Multiple CGPU VM with Nvidia Driver pre-installed image. 
cgpu_h100_onboarding() {
	while getopts t:s:r:l:p:i:e:d:c:a:v:o:n:-: flag
	do
	    case "${flag}" in
			t) tenant_id=${OPTARG};;
			s) subscription_id=${OPTARG};;
			r) rg=${OPTARG};;
			l) location=${OPTARG};;
			p) public_key_path=${OPTARG};;
			i) private_key_path=${OPTARG};;
			e) encryption_type=${OPTARG};;
			d) des_id=${OPTARG};;
			c) cgpu_package_path=${OPTARG};;
			a) adminuser_name=${OPTARG};;
			v) vmname_prefix=${OPTARG};;
			o) os_disk_size=${OPTARG};;
			n) total_vm_number=${OPTARG};;
			-) case "${OPTARG}" in
				skip-az-login) skip_az_login=true;;
			esac;;
	    esac
	done
	
	ONBOARDING_PACKAGE_VERSION="V3.0.10"
	echo "Confidential GPU H100 Onboarding Package Version: $ONBOARDING_PACKAGE_VERSION"

	if [ "$(az --version | grep azure-cli)" == "" ]; then
    		echo "Azure CLI is not installed, please try install Azure CLI first: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    		return
	fi

 	# Make sure Az CLI minimum version is met
        MINIMUM_AZ_CLI_VERSION="2.47.0"
        current_az_cli=$(az --version | grep azure-cli)
        if [[ $current_az_cli =~ [0-9.]+ ]]
        then
                az_cli_version="${BASH_REMATCH[0]}"
        fi
        echo -e "$MINIMUM_AZ_CLI_VERSION\n$az_cli_version" | sort --check=quiet --version-sort
        if [ "$?" -ne "0" ];
        then
		echo "Current Azure CLI version found: $az_cli_version, expected >=$MINIMUM_AZ_CLI_VERSION"
                az upgrade
        fi

	# Log out input information.
	echo "Tenant id: ${tenant_id}" 
	echo "subscription id: ${subscription_id}" 
	echo "Resource group: ${rg}" 

	# Checks region parameter, and sets to eastus2 if not otherwise specified
	if [[ -z "${location}" ]]; then
		echo "Location was not specified, setting to eastus2 region"
		location="eastus2"
	elif [[ "$location" == "eastus2" ]] || [[ "$location" == "westeurope" ]]; then
		echo "Allowed location selected"
	else
		echo "The selected location is not currently supported."
		return
	fi
 	echo "Location: ${location}" 

	echo "Public key path: ${public_key_path}" 
	if [ ! -f "${public_key_path}" ]; then
    		echo "${public_key_path} does not exist, please verify file path"
    		return
	fi

	echo "Private key path:  ${private_key_path}"
	if [ ! -f "${private_key_path}" ]; then
    		echo "${private_key_path} does not exist, please verify file path"
    		return
	fi

	if [[ -z "${encryption_type}" ]]; then
		echo "Encryption type was not specified, setting to DiskWithVMGuestState."
		encryption_type="DiskWithVMGuestState"
	elif [[ "${encryption_type}" != "DiskWithVMGuestState" && -n "${des_id}" ]]; then
		echo "CMK only supports encryption type DiskWithVMGuestState."
		return
	elif [[ "$encryption_type" == "DiskWithVMGuestState" ]] || [[ "$encryption_type" == "VMGuestStateOnly" ]]; then
		echo "Allowed encryption type set."
	else
		echo "Encryption type must be DiskWithVMGuestState or VMGuestStateOnly."
		return
	fi
 	echo "Encryption type: ${encryption_type}"

	echo "Disk encryption Id: ${des_id}"

	echo "Cgpu onboarding package path:  ${cgpu_package_path}"
	if [ ! -f "${cgpu_package_path}" ]; then
    		echo "${cgpu_package_path} does not exist, please verify file path"
    		return
	fi

	echo "Admin user name:  ${adminuser_name}"
	echo "Vm Name prefix:  ${vmname_prefix}"

	# Makes sure the OS disk size is set to an allowed value
	if [[ -z "${os_disk_size}" ]]; then
		echo "OS disk size was not specified, setting to 100 GB."
		os_disk_size=100
	elif test "${os_disk_size}" -ge 30 && test "${os_disk_size}" -le 4095; then
		echo "Allowed OS disk size set."
	else
		echo "OS disk size must be between 30 GB and 4095 GB."
		return
	fi
 	echo "OS disk size: ${os_disk_size}" 

	echo "Total VM number:  ${total_vm_number}"

	if [[ -n "${skip_az_login}" ]]; then
		echo "Skipping az login"
	else
		echo "Clear previous account info."
		az account clear
		az login --tenant ${tenant_id} > "$log_dir/login-operation.log"
	fi

	az account set --subscription $subscription_id >> "$log_dir/login-operation.log"
	az config set core.display_region_identified=false

	current_log_file="$log_dir/login-operation.log"
	prepare_subscription_and_rg >> "$log_dir/login-operation.log"
	if [ "$is_success" == "failed" ]; then
		echo "failed to prepare_subscription_and_rg." 
		return
	fi
	echo "prepare subscription and resource group success."

	# Start VM creation with number of specified VMs.
	successCount=0
	for ((current_vm_count=1; current_vm_count <= total_vm_number; current_vm_count++))
	do
		is_success="Succeeded"
		if [ $current_vm_count == 1 ];
		then 
			vmname="${vmname_prefix}";
		else 
			vmname_ending=$(($current_vm_count));
			vmname="${vmname_prefix}-${vmname_ending}"
    		fi

		echo "Vm Name: ${vmname}";
		auto_onboard_cgpu_single_vm $vmname
		if [[ $is_success != "failed" ]]
		then
			validation
			if [[ "$is_success" == "Succeeded" ]];
			then 
				successCount=$(($successCount+1))
			fi
			echo "Current number of VM finished: ${current_vm_count}, total Success: ${successCount}."
		fi
	done

	echo "Total VM to onboard: ${total_vm_number}, total Success: ${successCount}."
	echo "******************************************************************************************"
	echo "Please execute below commands to login to your VM:"
	for ((i=1; i <= total_vm_number; i++))
	do
		echo "ssh -i $private_key_path ${vm_ssh_info_arr[i]}" 
	done

	echo "Please execute the below command to try attestation:"
	echo "cd cgpu-onboarding-package; sudo bash step-2-attestation.sh";
	echo "Please execute the below command to try a sample workload:"
	echo "sudo docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -v /home/${adminuser_name}/cgpu-onboarding-package:/home -it --rm nvcr.io/nvidia/tensorflow:24.05-tf2-py3 python /home/mnist-sample-workload.py";
	echo "******************************************************************************************"

	if [[ -z "${skip_az_login}" ]]; then
		az account clear
	fi
}

# Checks that user has access to direct share image
check_image_access() {
	echo "Checking for direct share image permission access"
	if [ "$(az sig list-shared --location $location | grep -i "testGalleryDeirectShare")" == "" ]; then
		print_error "Couldn't access direct share image from your subscription or tenant. Please make sure you have the necessary permissions."
		is_success="failed"
		return
	fi 
}

# Login to subscription and check resource group. 
# It will create an resource group if it doesn't exist.
prepare_subscription_and_rg() {
	if [ "$(az account show | grep $subscription_id)" == "" ]; then
		print_error "Couldn't set to the correct subscription, please confirm and re-login with your azure account."
		is_success="failed"
		return
	fi 
	
	print_error "SubscriptionId validation success."
	print_error "Checking resource group...."
	
	# azure cli return invisible char, removing it.
	is_resource_group_exist="$(az group exists --name $rg)"
	is_resource_group_exist=$(echo "$is_resource_group_exist" | tr -cd '[:alnum:]-/,.:@')
	
	if [ $is_resource_group_exist == "false" ]; then
    	print_error "Resource group ${rg} does not exist, start creating resource group ${rg}"
    	
    	az group create --name ${rg} --location ${location}

    	# azure cli return invisible char, removing it.
    	is_resource_group_exist="$(az group exists --name $rg)"
    	is_resource_group_exist=$(echo "$is_resource_group_exist" | tr -cd '[:alnum:]-/,.:@')
		
		if [ $is_resource_group_exist == "false" ]; then
			print_error "rg creation failed, please check if your subscription is correct."
			is_success="failed"
			return
		fi
		print_error "Resource group ${rg} create success."
	fi

	print_error "Resource group ${rg} validation Succeeded."
}

# Create a single VM and onboard confidential gpu.
auto_onboard_cgpu_single_vm() {
	local vmname=$1
	create_vm $vmname
	if [[ $is_success == "failed" ]]; then
		echo "VM creation failed"
		return
	fi
	ip=$(az vm show -d -g $rg -n $vmname --query publicIps -o tsv)

	# azure cli return invisible char, removing it.
	vm_ssh_info="${adminuser_name}@${ip}"
	vm_ssh_info=$(echo "$vm_ssh_info" | tr -cd '[:alnum:]-/,.:@')

	echo "VM creation finished"
	echo $vm_ssh_info

	# Upload customer onboarding package.
	upload_package
	
	# Update kernel
	update_kernel

	# Install Nvidia gpu driver
	install_gpu_driver

	# Attestation.
	attestation

	# Install docker gpu tools
	install_gpu_tool
	
	vm_ssh_info_arr[$current_vm_count]=$vm_ssh_info
}

# Upload package to VM.
upload_package() {
	try_connect

	echo "Start uploading package..."
	scp -i $private_key_path $cgpu_package_path $vm_ssh_info:/home/$adminuser_name
	echo "Finished uploading package."

	echo "Start extracting package..."
	ssh -i $private_key_path $vm_ssh_info "tar -zxvf cgpu-onboarding-package.tar.gz;"
	echo "Finished extracting package."
}

# Upload package to VM.
update_kernel() {
	try_connect
	echo "Start update kernel."
	ssh -i $private_key_path $vm_ssh_info "cd cgpu-onboarding-package; bash step-0-prepare-kernel.sh;" 
	echo "Finished update kernel."
	echo "Rebooting.."
}

install_gpu_driver() {
	try_connect
	echo "Start install gpu driver"
	ssh -i $private_key_path $vm_ssh_info "cd cgpu-onboarding-package; bash step-1-install-gpu-driver.sh;" 
	echo "Finished install gpu driver"
}

# Do attestation in the created VMs.
attestation() {
	try_connect
	echo "Start verifier installation and attestation. Please wait, this process can take up to 2 minutes."
	ssh -i $private_key_path $vm_ssh_info "cd cgpu-onboarding-package; echo Y | bash step-2-attestation.sh;"
	#ssh -i $private_key_path $vm_ssh_info 'cd cgpu-onboarding-package/$(ls -1 cgpu-onboarding-package | grep verifier | head -1); sudo python3 cc_admin.py'
	echo "Finished attestation."
}

install_gpu_tool() {
	try_connect
	echo "Start install gpu tool."
	ssh -i $private_key_path $vm_ssh_info "cd cgpu-onboarding-package; echo Y | bash step-3-install-gpu-tools.sh;" 
	echo "Finished install gpu tool."
}

# Try to connect to VM with 50 maximum retry.
try_connect() {
   echo "Starting trying to connect to VM"
   MAX_RETRY=50
   retries=0
   connectionoutput=""
   while [[ "$connectionoutput" != "Connected to VM" ]] && [[ $retries -lt $MAX_RETRY ]];
   do
       connectionoutput=$(ssh -i "${private_key_path}" -o "StrictHostKeyChecking=no" "${vm_ssh_info}" "echo 'Connected to VM';")
       echo $connectionoutput
	   sleep 1
       retries=$((retries+1))
   done
}

# Create a single VM.
create_vm() {
	local vmname=$1
	echo "Start creating VM: '${vmname}'. Please wait, this process can take up to 10 minutes."

	public_key_path_with_at="@$public_key_path"
	image_version="latest"

	# Check if VM name already exists within given resource group (returns 1 if exists, 0 if not)
	vm_count=$(az vm list --resource-group $rg --query "[?name=='$vmname'] | length(@)")
	vm_count=$(echo "$vm_count" | tr -cd '[:alnum:]-/,.:@')
	if [ $vm_count -eq 0 ]; then
		if [ -n "$des_id" ]; then
			echo "Disk encryption set ID has been set, using Customer Managed Key for VM creation:"
			echo "Provisioning VM..."
			az vm create \
				--resource-group $rg \
				--name $vmname \
				--location $location \
				--image Canonical:0001-com-ubuntu-confidential-vm-jammy:22_04-lts-cvm:$image_version \
				--public-ip-sku Standard \
				--admin-username $adminuser_name \
				--ssh-key-values $public_key_path_with_at \
				--security-type ConfidentialVM \
				--os-disk-security-encryption-type DiskWithVMGuestState \
				--os-disk-secure-vm-disk-encryption-set $des_id \
				--enable-secure-boot true \
				--enable-vtpm true \
				--size Standard_NCC40ads_H100_v5 \
				--os-disk-size-gb $os_disk_size \
				--verbose
		else
			echo "Disk encryption set ID is not set, using Platform Managed Key for VM creation"
			echo "Provisioning VM..."
			az vm create \
				--resource-group $rg \
				--name $vmname \
				--location $location \
				--image Canonical:0001-com-ubuntu-confidential-vm-jammy:22_04-lts-cvm:$image_version \
				--public-ip-sku Standard \
				--admin-username $adminuser_name \
				--ssh-key-values $public_key_path_with_at \
				--security-type ConfidentialVM \
				--os-disk-security-encryption-type $encryption_type \
				--enable-secure-boot true \
				--enable-vtpm true \
				--size Standard_NCC40ads_H100_v5 \
				--os-disk-size-gb $os_disk_size \
				--verbose
		fi

		if [[ $? -ne 0 ]]; then
			is_success="failed"
			return
		fi
	else
		echo "A virtual machine with the name $vmname already exists in $rg - please choose a unique name."
		is_success="failed"
		return
	fi
}

validation() {
	echo "Validate Confidential GPU capability."
	try_connect
	
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
		echo "Failed: Confidential Compute mode validation failed. Current Confidential Compute retrieve state: ${cc_retrieve}"
	else 
		echo "Passed: Confidential Compute mode validation passed. Current Confidential Compute retrieve state: ${cc_retrieve}"
	fi

	cc_environment=$(ssh -i $private_key_path $vm_ssh_info "nvidia-smi conf-compute -e;")
	if [ "$cc_environment" != "CC Environment: PRODUCTION" ];
	then
		is_success="failed"
		echo "Failed: Confidential Compute environment validation. Current Confidential Compute environment: ${cc_environment}"
	else 
		echo "Passed: Confidential Compute environment validation. Current Confidential Compute environment: ${cc_environment}"

	fi
}

print_error() {
	echo $1 1>&2
	echo $1 >> "$current_log_file"
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
	log_time=$(date '+%Y-%m-%d-%H%M%S')
	log_dir="logs/$log_time"
	mkdir -p "$log_dir"

	cgpu_h100_onboarding "$@" 2>&1 > "$log_dir/current-operation.log" &
	last_pid=$!
	tail -f "$log_dir/current-operation.log" &
	wait $last_pid && kill $!
fi
