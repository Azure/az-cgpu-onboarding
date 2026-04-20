## This module helps install associate dependency and do attestation against CGPU driver.
##
## Requirements:
##      Minimum Nvidia driver:      v570.86.15
##      Minimum kernel version:     6.5.0-1017-azure
##
## Example:
##      sudo bash step-2-attestation.sh                      # Run both CPU and GPU attestation
##      sudo bash step-2-attestation.sh --cpu-only           # Run CPU attestation only
##      sudo bash step-2-attestation.sh --gpu-only           # Run GPU attestation only
##

INSTALL_TO_USR_LOCAL=1
RUN_CPU=1
RUN_GPU=1
CREATE_CPU_ATTESTATION_ALIAS=1
CREATE_GPU_ATTESTATION_ALIAS=1
GPU_ATTESTATION_CMD="/usr/local/bin/gpu-attestation"
CPU_ATTESTATION_CMD="/usr/local/bin/cpu-attestation"
NVIDIA_PERSISTENCED_WAIT_TIMEOUT=60
CVM_ATTESTATION_RELEASE_URL="https://github.com/Azure/cvm-attestation-tools/releases/download/v1.0.26/attest-lin.zip"

# Common apt-get options: lock timeout, retry limit, and network timeouts
APT_OPTS="-o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --install-to-usr-local)
            INSTALL_TO_USR_LOCAL=1
            ;;
        --cpu-only)
            RUN_CPU=1
            RUN_GPU=0
            ;;
        --gpu-only)
            RUN_CPU=0
            RUN_GPU=1
            ;;
        *)
            echo "Invalid argument: $arg"
            echo "Usage: $0 [--cpu-only | --gpu-only] [--install-to-usr-local]"
            exit 1
            ;;
    esac
done

gpu_preflight_checks() {
    # Wait for nvidia-persistenced to be ready (started by step-1)
    echo "Waiting for nvidia-persistenced to be ready ..."
    for i in $(seq 1 $NVIDIA_PERSISTENCED_WAIT_TIMEOUT); do
        if systemctl is-active --quiet nvidia-persistenced; then
            echo "nvidia-persistenced is active."
            break
        fi
        if [ "$i" -eq "$NVIDIA_PERSISTENCED_WAIT_TIMEOUT" ]; then
            echo "ERROR: nvidia-persistenced did not become active within ${NVIDIA_PERSISTENCED_WAIT_TIMEOUT} seconds."
            return 1
        fi
        sleep 1
    done

    # Verify persistence mode is enabled on all GPUs
    local smi_output
    if ! smi_output=$(nvidia-smi --query-gpu=persistence_mode --format=csv,noheader); then
        echo "ERROR: nvidia-smi failed. Please check if the driver is loaded correctly."
        return 1
    fi
    if echo "$smi_output" | grep -qv "Enabled"; then
        echo "ERROR: GPU persistence mode is not enabled on all GPUs."
        nvidia-smi --query-gpu=index,persistence_mode --format=csv
        return 1
    fi
    echo "GPU persistence mode is enabled on all GPUs."
}

gpu_attestation() {
    echo "============================================================"
    echo "  GPU Attestation"
    echo "============================================================"

    # Install Python3 pip and venv
    sudo apt-get $APT_OPTS update
    sudo apt-get $APT_OPTS install -y python3-pip python3-venv

    if [ "$INSTALL_TO_USR_LOCAL" = "1" ]; then
        echo "Installing local_gpu_verifier in /usr/local/lib"
        local install_dir="/usr/local/lib/local_gpu_verifier"
    else
        echo "Installing local_gpu_verifier in script directory $SCRIPT_DIR"
        local install_dir="$SCRIPT_DIR/local_gpu_verifier"
    fi

    # Remove existing folder if present
    if [ -d "$install_dir" ]; then
        echo "Removing existing $install_dir"
        sudo rm -rf "$install_dir"
    fi

    sudo mkdir -p "$install_dir"
    sudo tar -xvf "$SCRIPT_DIR/local_gpu_verifier.tar" -C "$install_dir"
    pushd "$install_dir" >/dev/null

    echo "Open verifier folder successfully!"
    sudo rm -rf ./prodtest
    sudo python3 -m venv ./prodtest
    sudo ./prodtest/bin/python3 -m pip install .

    # Create gpu-attestation command alias for easier usage
    if [ "$INSTALL_TO_USR_LOCAL" = "1" ] && [ "$CREATE_GPU_ATTESTATION_ALIAS" = "1" ]; then
        echo "Creating $GPU_ATTESTATION_CMD command ..."
        (echo '#!/usr/bin/env bash'
         echo "NVIDIA_PERSISTENCED_WAIT_TIMEOUT=$NVIDIA_PERSISTENCED_WAIT_TIMEOUT"
         declare -f gpu_preflight_checks
         echo 'gpu_preflight_checks || exit 1'
         echo "cd $install_dir"
         echo "./prodtest/bin/python3 -m verifier.cc_admin \"\$@\""
        ) | sudo tee $GPU_ATTESTATION_CMD >/dev/null
        sudo chmod +x $GPU_ATTESTATION_CMD
        echo "gpu-attestation command installed. Run 'sudo gpu-attestation' from anywhere."
    fi
    popd >/dev/null

    # Run GPU attestation
    if [ -x $GPU_ATTESTATION_CMD ]; then
        sudo $GPU_ATTESTATION_CMD
    else
        gpu_preflight_checks || return 1
        pushd "$install_dir" >/dev/null
        sudo ./prodtest/bin/python3 -m verifier.cc_admin
        popd >/dev/null
    fi

    # Copy verifier.log back to script directory when installed to /usr/local
    if [ "$INSTALL_TO_USR_LOCAL" = "1" ] && [ -f "$install_dir/verifier.log" ]; then
        local log_dest="$SCRIPT_DIR/local_gpu_verifier"
        sudo mkdir -p "$log_dest"
        sudo cp "$install_dir/verifier.log" "$log_dest/verifier.log"
        echo "Copied verifier.log to $log_dest/verifier.log"
    fi
}

cpu_attestation() {
    echo "============================================================"
    echo "  CVM (CPU) Attestation"
    echo "============================================================"

    if [ "$INSTALL_TO_USR_LOCAL" = "1" ]; then
        local install_dir="/usr/local/lib/cvm-attestation"
    else
        local install_dir="$SCRIPT_DIR/cvm-attestation"
    fi

    # Download and extract cvm-attestation-tools release
    echo "Downloading cvm-attestation-tools from $CVM_ATTESTATION_RELEASE_URL ..."
    local tmpzip
    tmpzip=$(mktemp /tmp/attest-lin.XXXXXX.zip)
    curl -fsSL -o "$tmpzip" "$CVM_ATTESTATION_RELEASE_URL"

    sudo mkdir -p "$install_dir"
    sudo apt-get $APT_OPTS install -y unzip
    sudo unzip -o "$tmpzip" -d "$install_dir"
    rm -f "$tmpzip"

    sudo chmod +x "$install_dir/attest" "$install_dir/read_report" 2>/dev/null || true

    echo "CVM attestation tools installed to $install_dir"

    # Create cpu-attestation command alias
    if [ "$INSTALL_TO_USR_LOCAL" = "1" ] && [ "$CREATE_CPU_ATTESTATION_ALIAS" = "1" ]; then
        echo "Creating $CPU_ATTESTATION_CMD command ..."
        (echo '#!/usr/bin/env bash'
         echo "cd $install_dir"
         echo "./attest --c ./config_snp.json \"\$@\""
        ) | sudo tee $CPU_ATTESTATION_CMD >/dev/null
        sudo chmod +x $CPU_ATTESTATION_CMD
        echo "cpu-attestation command installed. Run 'sudo cpu-attestation' from anywhere."
    fi

    # Run CPU attestation
    if [ -x $CPU_ATTESTATION_CMD ]; then
        sudo $CPU_ATTESTATION_CMD
    else
        sudo "$install_dir/attest" --c "$install_dir/config_snp.json"
    fi
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    echo -e "\n===== [step-2-attestation.sh] $(date) =====" | tee logs/current-operation.log | tee -a logs/all-operation.log
    if [ "$RUN_CPU" = "1" ]; then
        cpu_attestation "$@" 2>&1 | tee -a logs/current-operation.log | tee -a logs/all-operation.log
    fi
    if [ "$RUN_GPU" = "1" ]; then
        gpu_attestation "$@" 2>&1 | tee -a logs/current-operation.log | tee -a logs/all-operation.log
    fi
fi
