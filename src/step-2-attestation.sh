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
AZURE_GUEST_ATTEST_RELEASE_URL="https://github.com/Azure/azure-guest-attestation-sdk/releases/download/azure-guest-attest-v0.1.0/azure-guest-attest-x86_64-unknown-linux-musl"
CONDA_INSTALL_DIR="/opt/miniconda3"
CONDA_INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
CONDA_EXECUTABLE=""
CONDA_PYTHON_VERSION="3.12"

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

install_conda() {
    local conda_candidate
    conda_candidate=$(type -P conda || true)

    # Prefer a functional Conda already available on PATH.
    if [ -n "$conda_candidate" ] && "$conda_candidate" --version >/dev/null 2>&1; then
        CONDA_EXECUTABLE="$conda_candidate"
        echo "Using existing Conda installation: $CONDA_EXECUTABLE"
        return 0
    fi
    # Reuse the managed installation from a previous run when it is not on PATH.
    if [ -x "$CONDA_INSTALL_DIR/bin/conda" ] && "$CONDA_INSTALL_DIR/bin/conda" --version >/dev/null 2>&1; then
        CONDA_EXECUTABLE="$CONDA_INSTALL_DIR/bin/conda"
        echo "Using existing Conda installation: $CONDA_EXECUTABLE"
        return 0
    fi

    # Install Miniconda only when neither reusable option is available.
    sudo apt-get $APT_OPTS update || return 1
    sudo apt-get $APT_OPTS install -y curl ca-certificates || return 1
    echo "Installing the latest Miniconda in $CONDA_INSTALL_DIR ..."

    local conda_installer
    conda_installer=$(mktemp /tmp/miniconda.XXXXXX.sh)
    if ! curl -fsSL "$CONDA_INSTALLER_URL" -o "$conda_installer"; then
        rm -f "$conda_installer"
        echo "ERROR: Failed to download Miniconda."
        return 1
    fi

    if [ -e "$CONDA_INSTALL_DIR" ]; then
        # A partial or broken installation blocks Miniconda from using this prefix.
        echo "Removing unusable Conda installation from $CONDA_INSTALL_DIR ..."
        sudo rm -rf "$CONDA_INSTALL_DIR"
    fi
    if ! sudo bash "$conda_installer" -b -p "$CONDA_INSTALL_DIR"; then
        rm -f "$conda_installer"
        echo "ERROR: Failed to install Miniconda."
        return 1
    fi
    rm -f "$conda_installer"
    CONDA_EXECUTABLE="$CONDA_INSTALL_DIR/bin/conda"
    if ! "$CONDA_EXECUTABLE" --version >/dev/null 2>&1; then
        echo "ERROR: Miniconda installation is not functional."
        return 1
    fi
}

gpu_attestation() {
    echo "============================================================"
    echo "  GPU Attestation"
    echo "============================================================"

    install_conda || return 1

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
    # Restrict runtime packages to conda-forge; pip installs verifier dependencies from PyPI.
    sudo rm -rf ./.venv
    if ! sudo "$CONDA_EXECUTABLE" create --yes --override-channels --channel conda-forge --prefix ./.venv "python=$CONDA_PYTHON_VERSION"; then
        echo "ERROR: Failed to create the Python $CONDA_PYTHON_VERSION Conda environment."
        popd >/dev/null
        return 1
    fi
    if ! sudo ./.venv/bin/python -m pip install .; then
        echo "ERROR: Failed to install local_gpu_verifier."
        popd >/dev/null
        return 1
    fi

    # Create gpu-attestation command alias for easier usage
    if [ "$INSTALL_TO_USR_LOCAL" = "1" ] && [ "$CREATE_GPU_ATTESTATION_ALIAS" = "1" ]; then
        echo "Creating $GPU_ATTESTATION_CMD command ..."
        (echo '#!/usr/bin/env bash'
         echo "NVIDIA_PERSISTENCED_WAIT_TIMEOUT=$NVIDIA_PERSISTENCED_WAIT_TIMEOUT"
         declare -f gpu_preflight_checks
         echo 'gpu_preflight_checks || exit 1'
         echo "cd $install_dir"
         echo "./.venv/bin/python -m verifier.cc_admin \"\$@\""
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
        sudo ./.venv/bin/python -m verifier.cc_admin
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
        local install_dir="/usr/local/lib/azure-guest-attest"
    else
        local install_dir="$SCRIPT_DIR/azure-guest-attest"
    fi
    local attest_bin="$install_dir/azure-guest-attest"

    # Download the azure-guest-attest CLI (single static binary) and verify its checksum
    echo "Downloading azure-guest-attest from $AZURE_GUEST_ATTEST_RELEASE_URL ..."
    local tmpbin
    tmpbin=$(mktemp /tmp/azure-guest-attest.XXXXXX)
    curl -fsSL -o "$tmpbin" "$AZURE_GUEST_ATTEST_RELEASE_URL"
    curl -fsSL -o "$tmpbin.sha256" "$AZURE_GUEST_ATTEST_RELEASE_URL.sha256"

    local expected_sha actual_sha
    expected_sha=$(awk '{print $1}' "$tmpbin.sha256")
    actual_sha=$(sha256sum "$tmpbin" | awk '{print $1}')
    if [ -z "$expected_sha" ] || [ "$expected_sha" != "$actual_sha" ]; then
        echo "ERROR: azure-guest-attest checksum mismatch (expected '$expected_sha', got '$actual_sha')."
        rm -f "$tmpbin" "$tmpbin.sha256"
        return 1
    fi

    sudo mkdir -p "$install_dir"
    sudo install -m 0755 "$tmpbin" "$attest_bin"
    rm -f "$tmpbin" "$tmpbin.sha256"

    echo "azure-guest-attest installed to $attest_bin"

    # Create cpu-attestation command alias
    if [ "$INSTALL_TO_USR_LOCAL" = "1" ] && [ "$CREATE_CPU_ATTESTATION_ALIAS" = "1" ]; then
        echo "Creating $CPU_ATTESTATION_CMD command ..."
        (echo '#!/usr/bin/env bash'
         echo "$attest_bin guest-attest --provider maa --decode \"\$@\""
        ) | sudo tee $CPU_ATTESTATION_CMD >/dev/null
        sudo chmod +x $CPU_ATTESTATION_CMD
        echo "cpu-attestation command installed. Run 'sudo cpu-attestation' from anywhere."
    fi

    # Run CPU attestation
    if [ -x $CPU_ATTESTATION_CMD ]; then
        sudo $CPU_ATTESTATION_CMD
    else
        sudo "$attest_bin" guest-attest --provider maa --decode
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
