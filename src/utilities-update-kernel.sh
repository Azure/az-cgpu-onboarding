## This module helps install/update kernel to given version. If not given version,
## It will try to update to default version "6.5.0-1024-azure".
##
## Requirements:
##      Minimum Nvidia driver:      v550.90.07
##      Minimum kernel version:     6.5.0-1024-azure
##
## Example:
##      bash utilities-update-kernel.sh
##      bash utilities-update-kernel.sh -k "6.5.0-1024-azure"
##

# Default Azure kernel version to be update to
DEFAULT_KERNEL_VERSION="6.5.0-1024-azure"

# Compare if two given version is matching or not.
# Return 0 if equal, 1 if the first version is greater, 2 if the first version is smaller
vercomp() {
    dpkg --compare-versions "$1" eq "$2"
    if [ $? -eq 0 ]; then
        return 0
    fi

    dpkg --compare-versions "$1" gt "$2"
    if [ $? -eq 0 ]; then
        return 1
    fi

    dpkg --compare-versions "$1" lt "$2"
    if [ $? -eq 0 ]; then
        return 2
    fi
}

# Update kernel to given version. If the given version is mismatch with the current
# kernel version, it will remove the current version, then install the expect kernel
# and issue an system reboot at the end. Otherwise if version matches, it is an no opt.
update_kernel() {

    while getopts k: flag; do
        case "${flag}" in
        k) new_kernel=${OPTARG} ;;
        esac
    done
    if [ -z ${new_kernel+x} ]; then
        echo "No argument selected. Use default kernel version $DEFAULT_KERNEL_VERSION"
        new_kernel=$DEFAULT_KERNEL_VERSION
    else
        echo "Updating to kernel: '$new_kernel'"
    fi

    current_kernel=$(uname -r)
    echo "Current kernel version: $current_kernel"

    vercomp $current_kernel $new_kernel
    result=$?

    if [ $result -eq 2 ]; then
        echo "Installed kernel ($current_kernel) is older than specified kernel ($new_kernel)"
        install_kernel
    elif [ $result -eq 1 ]; then
        echo "Installed kernel ($current_kernel) is newer than specified kernel ($new_kernel)"
        install_kernel
        install_kernel_result=$?
        if [ $install_kernel_result -ne 0 ]; then
            echo "Failed to install kernel $new_kernel"
            return 1
        fi
        echo "Removing existing kernel"
        wait_apt_lock
        sudo DEBIAN_FRONTEND=noninteractive apt-get --yes --force-yes -o \
            Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" remove -y \
            $current_kernel
    else
        echo "Kernel is already on specified version ($current_kernel)"
        return 0
    fi

    echo "Rebooting system"
    sudo reboot
}

# Install kernel to given version, it will reboot the system at the end.
install_kernel() {
    echo "Updating kernel"
    wait_apt_lock
    sudo apt-get update
    wait_apt_lock
    sudo apt-get -y install \
        linux-image-$new_kernel-fde \
        linux-tools-$new_kernel \
        linux-cloud-tools-$new_kernel \
        linux-headers-$new_kernel \
        linux-modules-$new_kernel \
        linux-modules-extra-$new_kernel
}

# Wait until apt lock is released until MAX_RETRY
wait_apt_lock() {
    local MAX_RETRY=5
    local count=0

    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        if [ $count -ge $MAX_RETRY ]; then
            echo "Maximum attempts reached and apt lock is not released. Exiting..."
            return 1
        fi

        echo "Waiting for other apt operations to finish...Sleeping for 10 seconds"
        sleep 10
        count=$((count + 1))
    done

    return 0
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    update_kernel "$@"
fi
