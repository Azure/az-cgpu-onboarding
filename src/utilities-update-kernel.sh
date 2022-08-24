## This module helps install/update kernel to given version. If not given version, 
## It will try to update to default version "5.15.0-1014-azure".
##
## Requirements: 
##      nvdia driver:       APM_470.10.07_5.11.0-1028.31.tar
##      kenrel version:     5.15.0-1014-azure
##
## Example: 
##      bash utilities-update-kernel.sh 
##      bash utilities-update-kernel.sh -k "5.15.0-1014-azure"
##

# Default Azure kernel version to be update to
DEFAULT_KERNEL_VERSION="5.15.0-1014-azure"


# Compare if two given version is matching or not.
vercomp () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=".-"
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

# Update kernel to given version. If the given version is mismatch with the current
# kernel version, it will remove the current version, then install the expect kernel
# and issue an system reboot at the end. Otherwise if version matches, it is an no opt.
update_kernel(){

    while getopts k: flag
    do
        case "${flag}" in
            k) new_kernel=${OPTARG};;
        esac
    done
    if [ -z ${new_kernel+x} ]; then
        echo "No argument selected. Use default kernel version 5.15.0-1014-azure " 
        new_kernel=$DEFAULT_KERNEL_VERSION
    else
        echo "Updating to kernel: '$new_kernel'"
    fi

    current_kernel=$(uname -r)
    echo "Current kernel version: $current_kernel"

    vercomp $current_kernel $new_kernel
    result=$?

    if [ $result -eq 2 ]; then
        install_kernel
    elif  [ $result -eq 1 ]; then
        echo "Installed kernel ($current_kernel) is newer than specified kernel ($new_kernel)"
        echo "Removing existing kernel"
        sudo DEBIAN_FRONTEND=noninteractive apt-get --yes --force-yes -o \
            Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" remove -y \
            $current_kernel
        install_kernel 
        
    else
        echo "Kernel is already on specified version ($current_kernel)"
    fi
}

# Install kernel to given version, it will reboot the system at the end.
install_kernel(){
    echo "Updating kernel"
    sudo apt-get update

    sudo apt-get -y install linux-image-$new_kernel \
    linux-tools-$new_kernel \
    linux-cloud-tools-$new_kernel \
    linux-headers-$new_kernel \
    linux-modules-$new_kernel \
    linux-modules-extra-$new_kernel

    sudo reboot
}


if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    update_kernel "$@"
fi
