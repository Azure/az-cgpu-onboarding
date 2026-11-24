#!/usr/bin/env bash
# Run the legacy Python GPU verifier locally without changing gpu-attestation.
# Usage: sudo bash utilities-legacy-local-gpu-verifier.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER_DIR="$SCRIPT_DIR/legacy_local_gpu_verifier"
NVIDIA_PERSISTENCED_WAIT_TIMEOUT=60
APT_OPTS="-o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"
CONDA_INSTALL_DIR="/opt/miniconda3"
CONDA_INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
CONDA_DOWNLOAD_RETRIES=3
CONDA_EXECUTABLE=""
CONDA_PYTHON_VERSION="3.12"

if [ "$#" -ne 0 ]; then
    echo "Usage: sudo bash utilities-legacy-local-gpu-verifier.sh" >&2
    exit 1
fi

gpu_preflight_checks() {
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
    if [ -n "$conda_candidate" ] && "$conda_candidate" --version >/dev/null 2>&1; then
        CONDA_EXECUTABLE="$conda_candidate"
        echo "Using existing Conda installation: $CONDA_EXECUTABLE"
        return 0
    fi
    if [ -x "$CONDA_INSTALL_DIR/bin/conda" ] && "$CONDA_INSTALL_DIR/bin/conda" --version >/dev/null 2>&1; then
        CONDA_EXECUTABLE="$CONDA_INSTALL_DIR/bin/conda"
        echo "Using existing Conda installation: $CONDA_EXECUTABLE"
        return 0
    fi
    sudo apt-get $APT_OPTS update || return 1
    sudo apt-get $APT_OPTS install -y curl ca-certificates || return 1
    echo "Installing the latest Miniconda in $CONDA_INSTALL_DIR ..."

    local conda_installer
    conda_installer=$(mktemp /tmp/miniconda.XXXXXX.sh)
    if ! curl -fsSL --retry "$CONDA_DOWNLOAD_RETRIES" --retry-all-errors "$CONDA_INSTALLER_URL" -o "$conda_installer"; then
        rm -f "$conda_installer"
        echo "ERROR: Failed to download Miniconda."
        return 1
    fi
    if [ -e "$CONDA_INSTALL_DIR" ]; then
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
    install_conda || return 1
    sudo mkdir -p "$VERIFIER_DIR" || return 1
    sudo tar -xf "$SCRIPT_DIR/legacy_local_gpu_verifier.tar" -C "$VERIFIER_DIR" || return 1
    (
        cd "$VERIFIER_DIR" || exit 1
        sudo rm -rf ./.venv || exit 1
        sudo "$CONDA_EXECUTABLE" create --yes --override-channels --channel conda-forge --prefix ./.venv "python=$CONDA_PYTHON_VERSION" || exit 1
        sudo ./.venv/bin/python -I -m pip install . || exit 1
        sudo ./.venv/bin/python -I -m pip check || exit 1
        gpu_preflight_checks || exit 1
        sudo ./.venv/bin/python -I -m verifier.cc_admin
    )
}

if [[ "${#BASH_SOURCE[@]}" -eq 1 ]]; then
    if [ ! -d "logs" ]; then
        mkdir logs
    fi
    echo -e "\n===== [utilities-legacy-local-gpu-verifier.sh] $(date) =====" | tee logs/current-operation.log | tee -a logs/all-operation.log
    gpu_attestation 2>&1 | tee -a logs/current-operation.log | tee -a logs/all-operation.log
    exit "${PIPESTATUS[0]}"
fi