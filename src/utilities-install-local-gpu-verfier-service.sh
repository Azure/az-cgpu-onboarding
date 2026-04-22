#!/bin/bash

## This module helps install and enable local GPU verifier attestation service.
##
## Example:
##      sudo bash utilities-install-local-gpu-verifier-service.sh
##

install_gpu_verifier_service() {
    echo "===================================================="
    echo "INSTALLING LOCAL GPU VERIFIER ATTESTATION SERVICE"
    echo "===================================================="

    service_install_dir="/usr/local/lib/local_gpu_verifier_http_service"

    echo "Checking for existing installation..."
    if [ -d "$service_install_dir" ]; then
        echo "Removing existing service installation directory..."
        sudo rm -rf "$service_install_dir"
    fi

    echo "Creating installation directory..."
    sudo mkdir -p "$service_install_dir"

    echo "Extracting service files..."
    sudo tar -xvf local_gpu_verifier_http_service.tar -C "$service_install_dir"

    echo "Running installation script..."
    cd "$service_install_dir"
    sudo bash ./install.sh --enable-service

    echo "Local GPU verifier attestation service has been enabled."
    echo "Waiting for service to fully start..."
    sleep 5
}

test_gpu_verifier_service() {
    echo "===================================================="
    echo "TESTING LOCAL GPU VERIFIER ATTESTATION SERVICE"
    echo "===================================================="

    # Check service status
    echo "Checking service status:"
    sudo systemctl status local-gpu-attestation --no-pager
    service_status=$?

    if [ $service_status -ne 0 ]; then
        echo "WARNING: Service status check returned non-zero status. Tests might fail."
    else
        echo "Service is running."
    fi

    # Generate random nonce for testing
    nonce=$(openssl rand -hex 32)
    echo "Using nonce: $nonce for testing"

    # Variables for test status
    http_status=1
    socket_status=1

    # Test HTTP port
    echo -e "\n----------------------------------------------------"
    echo "TESTING HTTP ENDPOINT (PORT 8123)"
    echo "----------------------------------------------------"

    http_curl_cmd="curl -s \"http://localhost:8123/gpu_attest?nonce=$nonce\""
    echo "Sending request to HTTP endpoint..."
    echo "$http_curl_cmd"
    http_result=$(eval $http_curl_cmd)
    http_status=$?

    if [ $http_status -eq 0 ]; then
        echo "HTTP request successful!"
        echo "Response:"
        echo "$http_result" | jq . 2>/dev/null || echo "$http_result"
    else
        echo "HTTP request failed with status: $http_status"
    fi

    # Test Unix socket
    echo -e "\n----------------------------------------------------"
    echo "TESTING UNIX SOCKET"
    echo "----------------------------------------------------"

    socket_path="/var/run/gpu-attestation/gpu-attestation.sock"

    if [ ! -S "$socket_path" ]; then
        echo "Error: Socket file not found at $socket_path"
        echo "Checking socket directory:"
        ls -la "$(dirname "$socket_path")"
    else
        echo "Socket file found at $socket_path"

        socket_curl_cmd="curl -s --unix-socket \"$socket_path\" \"http://localhost/gpu_attest?nonce=$nonce\""
        echo "Sending request to Unix socket..."
        echo "$socket_curl_cmd"
        socket_result=$(eval $socket_curl_cmd)
        socket_status=$?

        if [ $socket_status -eq 0 ]; then
            echo "Socket request successful!"
            echo "Response:"
            echo "$socket_result" | jq . 2>/dev/null || echo "$socket_result"
        else
            echo "Socket request failed with status: $socket_status"
            echo "Checking socket permissions:"
            ls -la "$socket_path"
        fi
    fi

    # Summary
    echo -e "\n===================================================="
    echo "TEST SUMMARY"
    echo "===================================================="
    echo "HTTP Test (port 8123): $([ $http_status -eq 0 ] && echo "SUCCESS" || echo "FAILED")"
    echo "Unix Socket Test: $([ $socket_status -eq 0 ] && echo "SUCCESS" || echo "FAILED")"

    if [ $http_status -eq 0 ] || [ $socket_status -eq 0 ]; then
        echo "Service is operational!"
    else
        echo "ERROR: Both HTTP and socket tests failed. Service might not be functioning correctly."
        echo "Check the logs with: sudo journalctl -u local-gpu-attestation"
    fi
}

install_and_test_gpu_verifier_service() {
    install_gpu_verifier_service
    test_gpu_verifier_service

}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    echo -e "\n===== [utilities-install-local-gpu-verfier-service.sh] $(date) =====" | tee logs/current-operation.log | tee -a logs/all-operation.log
    install_and_test_gpu_verifier_service "$@" 2>&1 | tee -a logs/current-operation.log | tee -a logs/all-operation.log
fi
