## This module helps install associate dependency and  do attestation against CGPU driver
##
## Requirements: 
##		nvdia driver:		APM_470.10.07_5.11.0-1028.31.tar
## 		kenrel version:		5.11.0-1028-azure
##		verifier:			verifier_apm_pid3.tar
##
## Example:
##		bash step-2-install-gpu-driver.sh
##


attestation(){
	tar -xvf verifier_apm_pid3_2.tar
	cd verifier_apm_pid3_2
	sudo apt install python3-pip
	sudo pip3 install -r requirements.txt
	sudo pip3 install -e pynvml_src/

	sudo python3 cc_admin.py
}



if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    attestation "$@"
fi
