## This module helps install associate dependency and  do attestation against CGPU driver.
##
## Requirements:
##		nvdia driver:		APM_470.10.07_5.11.0-1028.31.tar
## 		kenrel version:		5.11.0-1028-azure
##		verifier:			verifier_apm_pid3.tar
##
## Example:
##		bash step-2-install-gpu-driver.sh
##

REQUIRED_DRIVER_INTERFACE_VERSION="NVIDIA System Management Interface -- v470.10.10"

attestation(){
	current_driver_interface_version=$(sudo nvidia-smi -h | head -1)
    if [ "$current_driver_interface_version" != "$REQUIRED_DRIVER_INTERFACE_VERSION" ]; 
    then
    	echo "Current gpu driver version: ($current_driver_interface_version), Expected: ($REQUIRED_DRIVER_INTERFACE_VERSION)."
    	echo "Please retry step-2-install-gpu-driver."
    else 
    	echo "Driver verified successfully, start attestation."
		tar -xvf verifier_apm_pid3_3.tar
		cd verifier_apm_pid3_3
		sudo apt install python3-pip
		sudo pip3 install -r requirements.txt
		sudo pip3 install -e pynvml_src/

		sudo python3 cc_admin.py
	fi
}


if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    attestation "$@"
fi
