## This module helps install/update kernel to given version.
##
## Example:
##      bash utilities-update-kernel.sh -k "6.8.0-1044-azure-fde"
##      bash utilities-update-kernel.sh -k "6.8.0-1044-azure-fde" -d -r
##      bash utilities-update-kernel.sh -k "6.8.0-1044-azure-fde" -x -r
##
## Options:
##      -k, --kernel-version <version>    Target kernel version (required)
##      -r, --reboot-after-install        Reboot the system after kernel install (default: no reboot)
##      -d, --set-default-boot-kernel     Set the installed kernel as the default EFI boot entry
##      -x, --remove-other-kernels        Remove all other installed kernels except the target
##

# Common apt-get options: lock timeout, retry limit, network timeouts, and phased updates
APT_OPTS="-o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o APT::Get::Always-Include-Phased-Updates=true"

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

# Install the specified kernel version if it differs from the current one.
# Optionally sets it as the default EFI boot entry, removes other kernels, and reboots.
update_kernel() {

    local do_reboot=0
    local set_default=0
    local remove_others=0
    local new_kernel

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -k|--kernel-version) new_kernel="$2"; shift 2 ;;
            -r|--reboot-after-install) do_reboot=1; shift ;;
            -d|--set-default-boot-kernel) set_default=1; shift ;;
            -x|--remove-other-kernels) remove_others=1; shift ;;
            *) echo "Unknown argument: $1"; shift ;;
        esac
    done

    if [ -z "$new_kernel" ]; then
        echo "Error: -k <target_kernel_version> is required."
        echo "Usage: bash utilities-update-kernel.sh -k|--kernel-version <target_kernel_version> [-r|--reboot-after-install] [-d|--set-default-boot-kernel] [-x|--remove-other-kernels]"
        return 1
    fi
    echo "Updating to target kernel version: $new_kernel"

    current_kernel=$(uname -r)
    echo "Current kernel version: $current_kernel"

    vercomp $current_kernel $new_kernel
    result=$?

    if [ $result -eq 2 ]; then
        echo "Current kernel ($current_kernel) is older than the target kernel ($new_kernel)"
    elif [ $result -eq 1 ]; then
        echo "Current kernel ($current_kernel) is newer than the target kernel ($new_kernel)"
    else
        echo "Current kernel is already on the target version ($current_kernel)"
    fi

    if [ $result -ne 0 ]; then
        install_kernel
        if [ $? -ne 0 ]; then
            echo "Failed to install kernel $new_kernel"
            return 1
        fi
    fi

    # Set the target kernel as the default EFI boot entry
    if [ $set_default -eq 1 ]; then
        set_default_kernel "$new_kernel"
    fi

    # Remove all other installed kernels except the target
    if [ $remove_others -eq 1 ]; then
        remove_other_kernels "$new_kernel"
    fi

    if [ $do_reboot -eq 1 ]; then
        echo "Rebooting system"
        sudo reboot
    else
        echo "Reboot skipped. Run 'sudo reboot' manually to boot into $new_kernel."
    fi
}

# Install kernel to given version.
install_kernel() {
    echo "Updating kernel"
    sudo apt-get $APT_OPTS update
    sudo DEBIAN_FRONTEND=noninteractive apt-get $APT_OPTS -y install \
        "linux-image-${new_kernel}" \
        "linux-tools-${new_kernel}" \
        "linux-cloud-tools-${new_kernel}" \
        "linux-headers-${new_kernel}" \
        "linux-modules-${new_kernel}" \
        "linux-modules-extra-${new_kernel}"
}

# Set the specified kernel as the default EFI boot entry using efibootmgr.
# Finds the boot entry matching the target kernel and moves it to the front of BootOrder.
set_default_kernel() {
    local target_kernel="$1"
    echo "Setting kernel $target_kernel as the default boot entry..."

    if ! command -v efibootmgr >/dev/null 2>&1; then
        echo "ERROR: efibootmgr is not installed."
        return 1
    fi

    echo "Current EFI boot entries:"
    sudo efibootmgr -v

    # Find the boot entry number (e.g. "0003") whose description contains the target kernel
    local boot_num
    boot_num=$(sudo efibootmgr -v | grep -F "$target_kernel" | head -1 | awk '/Boot[0-9A-Fa-f]{4}/ {print substr($1, 5)}' | tr -d '*')

    if [ -z "$boot_num" ]; then
        echo "WARNING: Could not find EFI boot entry for kernel $target_kernel"
        echo "Available boot entries:"
        sudo efibootmgr | grep "^Boot"
        return 1
    fi

    echo "Found EFI boot entry: Boot$boot_num"

    # Get the current boot order and move the target entry to the front
    local current_order
    current_order=$(sudo efibootmgr | grep "^BootOrder:" | awk '{print $2}')

    if [ -z "$current_order" ]; then
        echo "ERROR: Could not read current BootOrder"
        return 1
    fi

    # Remove target from current order, then prepend it
    local new_order
    new_order=$(echo "$current_order" | tr ',' '\n' | grep -v "^${boot_num}$" | tr '\n' ',' | sed 's/,$//')
    if [ -z "$new_order" ]; then
        new_order="${boot_num}"
    else
        new_order="${boot_num},${new_order}"
    fi

    echo "Setting BootOrder: $new_order (was: $current_order)"
    sudo efibootmgr -o "$new_order"

    echo "Default boot kernel set to $target_kernel (Boot$boot_num)"
}

# Remove all installed kernel packages except those for the target kernel.
remove_other_kernels() {
    local target_kernel="$1"

    echo "Removing all kernel packages except target ($target_kernel)..."

    local packages_to_remove
    packages_to_remove=$(dpkg --list | grep -E 'linux-(image|headers|modules|tools|cloud-tools)-[0-9]' \
        | awk '{print $2}' | grep -v "$target_kernel")

    if [ -z "$packages_to_remove" ]; then
        echo "No other kernel packages to remove."
        return 0
    fi

    echo "Packages to remove:"
    echo "$packages_to_remove"

    sudo DEBIAN_FRONTEND=noninteractive apt-get $APT_OPTS --yes -o \
        Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
        purge -y $packages_to_remove

    echo "Finished removing other kernel packages."
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    update_kernel "$@"
fi
