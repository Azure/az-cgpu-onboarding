## This module helps install associate dependency and  do attestation against CGPU driver.
##
## Requirements:
##      nvdia driver:       APM_470.10.12_5.15.0-1014.17.tar
##      kernel version:     5.15.0-1014-azure
##      verifier:           verifier_apm_pid3_5_1.tar
##
## Example:
##      bash step-2-attestation.sh
## 

REQUIRED_DRIVER_INTERFACE_VERSION="NVIDIA System Management Interface -- v470.10.12"
MAX_RETRY=3

attestation(){
    # verify nvdia gpu driver has been install correctly.
    current_driver_interface_version=$(sudo nvidia-smi -h | head -1)
    if [ "$current_driver_interface_version" != "$REQUIRED_DRIVER_INTERFACE_VERSION" ]; 
    then
        echo "Current gpu driver version: ($current_driver_interface_version), Expected: ($REQUIRED_DRIVER_INTERFACE_VERSION)."
        echo "Please retry step-1-install-gpu-driver."
    else 
        echo "Driver verified successfully, start attestation."
        tar -xvf verifier_apm_pid3_5_1.tar
        cd verifier_apm_pid3_5_1
        sudo apt install python3-pip
        sudo pip3 install -r requirements.txt
        sudo pip3 install -e pynvml_src/

        sudo python3 cc_admin.py
        cd ..
        lockError=$(cat logs/current-operation.log | grep "Could not get lock")
        if [ "$lockError" != "" ] && [ $MAX_RETRY \> 0 ];
        then
            # start of retry, clean up current-operation log.
            MAX_RETRY=$((MAX_RETRY-1)) > logs/current-operation.log 
            echo "Found lock error retry attestation step."  
            echo "Retry left:"   
            echo $MAX_RETRY   
            sudo apt-get install -y libgl1 binutils xserver-xorg-core   
            sudo apt --fix-broken install   
            attestation "$@" 
        fi
    fi
}


if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ];
    then
        mkdir logs
    fi    
    attestation "$@" 2>&1 | tee logs/current-operation.log | tee -a logs/all-operation.log
fi
