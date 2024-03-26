## This module helps uninstall Nvidia r535 driver and unhold nvidia driver and linux kernels

# Unhold nvidia driver and linux kernels
sudo apt-mark unhold linux-azure-6.2 linux-image-6.2.0 linux-azure linux-headers-azure linux-image-azure linux-tools-azure linux-cloud-tools-azure
sudo apt-mark unhold $(sudo apt-mark showhold | grep -i nvidia)
sudo apt update

# Uninstall Nvidia r535 driver
sudo apt-get remove -y --purge *nvidia*535*
