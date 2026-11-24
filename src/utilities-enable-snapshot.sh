## This module enables or disables the Ubuntu snapshot selection for APT.
##
## Example:
##      sudo bash utilities-enable-snapshot.sh <timestamp> [--no-update]
##      sudo bash utilities-enable-snapshot.sh --disable
##

set -euo pipefail

enable_ubuntu_snapshot_service() {
    local TIMESTAMP="$1"
    local ubuntu_version APT_OPTS sources_list

    echo "Enabling Ubuntu snapshot service with timestamp: $TIMESTAMP"

    ubuntu_version=$(lsb_release -rs)
    APT_OPTS="-o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"

    # Ubuntu 22.04 uses traditional sources.list format and needs manual snapshot opt-in
    # Ubuntu 24.04+ has built-in snapshot support
    if dpkg --compare-versions "$ubuntu_version" "eq" "22.04"; then
        sources_list="/etc/apt/sources.list"
        sudo cp "$sources_list" "$sources_list.backup"
        sudo sed -i "/^\s*deb /{ /\[snapshot=yes\]/! s/deb /deb [snapshot=yes] / }" "$sources_list"
    fi

    echo "APT::Snapshot \"$TIMESTAMP\";" | sudo tee /etc/apt/apt.conf.d/50snapshot
    if [[ "${2:-}" != "--no-update" ]]; then
        sudo apt-get $APT_OPTS update
    fi
}

disable_ubuntu_snapshot_service() {
    local removed
    if removed=$(sudo rm -f -v -- /etc/apt/apt.conf.d/50snapshot); then
        if [ -z "$removed" ]; then
            echo "Ubuntu snapshot selection already disabled: /etc/apt/apt.conf.d/50snapshot is absent."
        else
            echo "Removed /etc/apt/apt.conf.d/50snapshot; Ubuntu snapshot selection disabled."
        fi
    else
        echo "ERROR: Failed to remove /etc/apt/apt.conf.d/50snapshot." >&2
        return 1
    fi
}

main() {
    if [[ "$#" -lt 1 || "$#" -gt 2 || -z "${1:-}" ||
        ( "$1" == -* && "$1" != "--disable" ) ||
        ( "$#" -eq 2 && "$2" != "--no-update" ) ]]; then
        echo "Error: Specify a snapshot timestamp with optional --no-update, or --disable." >&2
        echo "Usage: $0 <timestamp> [--no-update] | --disable" >&2
        return 1
    fi
    case "$1" in
        --disable) disable_ubuntu_snapshot_service ;;
        *) enable_ubuntu_snapshot_service "$@" ;;
    esac
}

main "$@"
