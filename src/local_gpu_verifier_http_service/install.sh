#!/usr/bin/env bash
#
# A script to build and install the local GPU attestation HTTP service.
#
# Usage:
#   cd local_gpu_verifier_http_service
#   sudo bash ./install.sh [--enable-service] [--enable-debug-log]
#

set -e

# Default values for arguments
ENABLE_SERVICE=0
ENABLE_DEBUG_LOG=0

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --enable-service)
            ENABLE_SERVICE=1
            ;;
        --enable-debug-log)
            ENABLE_DEBUG_LOG=1
            ;;
        *)
            echo "Invalid argument: $arg"
            echo "Usage: $0 [--enable-service] [--enable-debug-log]"
            exit 1
            ;;
    esac
done

# Go to the directory of this script
cd "$(dirname "$0")"

IMAGE_NAME="local_gpu_verifier_http_service_build"
LOCAL_GPU_VERIFIER_SERVICE_PATH="/usr/local/bin/local_gpu_verifier_http_service"
SERVICE_NAME="local-gpu-attestation"

# Clean up local go.mod and go.sum files and bin
rm -f ./go.mod ./go.sum
rm -rf ./bin

# Build the binary in a Docker container
echo "Building Docker image for local GPU attestation service..."
if [ "$ENABLE_DEBUG_LOG" = "1" ]; then
    echo "Debug logging is enabled."
    docker build -t "$IMAGE_NAME" --build-arg ENABLE_DEBUG_LOGGING=true .
else
    docker build -t "$IMAGE_NAME" --build-arg ENABLE_DEBUG_LOGGING=false .
fi

echo "Creating a temporary container..."
CONTAINER_ID=$(docker create "$IMAGE_NAME")

echo "Copying compiled binary from container to host..."
mkdir -p ./bin
docker cp "$CONTAINER_ID:/app/bin/local-gpu-attestation-http-service" ./bin/

echo "Removing temporary container..."
docker rm "$CONTAINER_ID"

# Stop the existing systemd service BEFORE copying the new binary if it's running
if [ "$ENABLE_SERVICE" = "1" ]; then
    echo "Stopping existing '$SERVICE_NAME' service (if running)..."
    sudo systemctl stop "$SERVICE_NAME" || true
fi

# Install the binary
echo "Installing local-gpu-attestation-http-service to $LOCAL_GPU_VERIFIER_SERVICE_PATH..."
sudo mkdir -p "$LOCAL_GPU_VERIFIER_SERVICE_PATH"
sudo cp ./bin/local-gpu-attestation-http-service "$LOCAL_GPU_VERIFIER_SERVICE_PATH"
sudo chmod +x "$LOCAL_GPU_VERIFIER_SERVICE_PATH/local-gpu-attestation-http-service"

echo "Installation complete!"
echo "Binary installed at: $LOCAL_GPU_VERIFIER_SERVICE_PATH/local-gpu-attestation-http-service"

# Enable and start the service
if [ "$ENABLE_SERVICE" = "1" ]; then
    echo "Setting up systemd service for '$SERVICE_NAME'..."
    sudo cp local-gpu-attestation.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME"
    echo "Service '$SERVICE_NAME' is enabled and running."
fi
