## This module enables the Ubuntu snapshot service for APT.
##
## Example:
##      sudo bash utilities-enable-snapshot.sh <timestamp>
##

if [[ -z "$1" ]]; then
    echo "Error: A snapshot timestamp is required."
    echo "Usage: $0 <timestamp>"
    exit 1
fi

TIMESTAMP="$1"

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
sudo apt-get $APT_OPTS update
