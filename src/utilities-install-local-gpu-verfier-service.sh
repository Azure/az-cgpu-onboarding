## This module helps install and enable local GPU verifier attestation HTTP service.
##
## Example:
##      sudo bash utilities-install-local-gpu-verifier-service.sh
##

service_install_dir="/usr/local/lib/local_gpu_verifier_http_service"

echo "Enabling local GPU verifier attestation service..."

if [ -d "$service_install_dir" ]; then
    echo "Removing existing service installation directory..."
    sudo rm -rf "$service_install_dir"
fi

sudo mkdir -p "$service_install_dir"
sudo tar -xvf local_gpu_verifier_http_service.tar -C "$service_install_dir"
cd "$service_install_dir"
sudo bash ./install.sh --enable-service
echo "Local GPU verifier attestation service has been enabled."

# Test the service
sleep 5
nonce=$(openssl rand -hex 32)
echo "Use nonce: $nonce"
echo "Sending request to local GPU verifier attestation service..."
curl -vs "http://localhost:8123/gpu_attest?nonce=$nonce"
