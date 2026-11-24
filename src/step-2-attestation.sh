## CPU attestation and NVIDIA nvattest GPU attestation (the default verifier).
##
## Requirements:
##      Minimum Nvidia driver:       v615.x (r615)
##      Minimum kernel version:      6.8.0-1068-azure-fde (Ubuntu 22.04)
##                                   7.0.0-1016-azure-fde (Ubuntu 24.04)
##
## Example:
##      sudo bash step-2-attestation.sh                      # Run both CPU and GPU attestation
##      sudo bash step-2-attestation.sh --cpu-only           # Run CPU attestation only
##      sudo bash step-2-attestation.sh --gpu-only           # Run GPU attestation only
##      sudo bash step-2-attestation.sh --gpu-only --rebuild-nvattest   # Rebuild nvattest, then run GPU attestation
##

set -euo pipefail

INSTALL_TO_USR_LOCAL=1
RUN_CPU=1
RUN_GPU=1
REBUILD_NVATTEST=0
CREATE_CPU_ATTESTATION_ALIAS=1
CREATE_GPU_ATTESTATION_ALIAS=1
GPU_ATTESTATION_CMD="/usr/local/bin/gpu-attestation"
CPU_ATTESTATION_CMD="/usr/local/bin/cpu-attestation"
AZURE_GUEST_ATTEST_RELEASE_URL="https://github.com/Azure/azure-guest-attestation-sdk/releases/download/azure-guest-attest-v0.1.0/azure-guest-attest-x86_64-unknown-linux-musl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APT_OPTS="-o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"

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
        --rebuild-nvattest)
            REBUILD_NVATTEST=1
            ;;
        *)
            echo "Invalid argument: $arg"
            echo "Usage: $0 [--cpu-only | --gpu-only] [--install-to-usr-local] [--rebuild-nvattest]"
            exit 1
            ;;
    esac
done

## Install Docker Engine for verifier builds.
install_docker() {
    if command -v docker >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
        echo "Docker client is installed and daemon is reachable; skipping Docker installation."
        return 0
    fi
    echo "Start docker installation."
    sudo apt-get $APT_OPTS update || return 1
    sudo apt-get $APT_OPTS install -y ca-certificates curl gnupg lsb-release || return 1
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || return 1

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null || return 1

    sudo apt-get $APT_OPTS update || return 1
    sudo apt-get $APT_OPTS install -y docker-ce docker-ce-cli containerd.io || return 1
    sudo docker run hello-world
}

gpu_preflight_checks() {
    local NVIDIA_PERSISTENCED_WAIT_TIMEOUT=60
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

thim_base_for_region() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        eastus2)       echo "https://useast2.thim.azure.net" ;;
        centraluseuap) echo "https://uscentraleuap.thim.azure.net" ;;
        westeurope)    echo "https://europewest.thim.azure.net" ;;
        centralus)     echo "https://uscentral.thim.azure.net" ;;
        *)             echo "" ;;
    esac
}

detect_azure_region() {
    curl -s -H "Metadata: true" --max-time 5 \
        "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null \
        | grep -o '"location":"[^"]*"' | head -1 | cut -d'"' -f4
}

run_gpu_attestation() {
    local WORK_DIR="${NVATTEST_DIR:-/usr/local/lib/new_local_gpu_verifier}"
    local OUT_BIN="$WORK_DIR/nvattest"
    local RP_POLICY="$WORK_DIR/nv_attest_gpu_verifier/azure_cgpu_h100_default_policy.rego"
    local ATTESTATION_LOG="$WORK_DIR/attestation.log"
    local NVIDIA_RIM_URL="https://rim.attestation.nvidia.com"
    local NVIDIA_OCSP_URL="https://ocsp.ndis.nvidia.com"
    local region thim_base rim_url="$NVIDIA_RIM_URL" ocsp_url rc=0
    local policy_args=()

    if [ "$#" -ne 0 ]; then
        echo "Usage: sudo gpu-attestation" >&2
        return 1
    fi
    gpu_preflight_checks || return 1
    if [ ! -f "$RP_POLICY" ]; then
        echo "ERROR: Required relying-party policy not found: $RP_POLICY" >&2
        return 1
    fi
    echo "Reusing the existing nvattest binary at $OUT_BIN."
    region="$(detect_azure_region)" || region=""
    thim_base="$(thim_base_for_region "$region")"
    if [ -z "$thim_base" ]; then
        ocsp_url="$NVIDIA_OCSP_URL"
        echo "Using NVIDIA RIM and OCSP for region '${region:-unknown}'."
    else
        rim_url="${thim_base}/nvidia"
        ocsp_url="${thim_base}/nvidia/ocsp/"
        policy_args=(--relying-party-policy "$RP_POLICY")
    fi

    echo "============================================================"
    echo "  GPU Attestation"
    echo "============================================================"
    echo "RIM: $rim_url"
    echo "OCSP: $ocsp_url"

    sudo "$OUT_BIN" attest --device gpu --verifier local \
        --rim-url "$rim_url" --ocsp-url "$ocsp_url" \
        --ocsp-cert-id-hash sha-384 \
        "${policy_args[@]}" \
        >"$ATTESTATION_LOG" 2>&1 || rc=$?

    if [ "$rc" -ne 0 ] && [ -n "$thim_base" ]; then
        echo "THIM attestation failed; retrying with NVIDIA RIM and OCSP." >&2
        {
            echo
            echo "THIM attestation failed; retrying with NVIDIA RIM and OCSP."
        } >>"$ATTESTATION_LOG"
        rc=0
        sudo "$OUT_BIN" attest --device gpu --verifier local \
            --rim-url "$NVIDIA_RIM_URL" --ocsp-url "$NVIDIA_OCSP_URL" \
            --ocsp-cert-id-hash sha-384 \
            "${policy_args[@]}" \
            >>"$ATTESTATION_LOG" 2>&1 || rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        sed '/^[[:space:]]*GPU attestation was successful[.!]*[[:space:]]*$/Id' \
            "$ATTESTATION_LOG"
        echo "GPU Attestation is Successful."
    else
        echo "GPU Attestation failed. Details: $ATTESTATION_LOG" >&2
    fi
    return "$rc"
}

gpu_attestation() {
    if [ "$INSTALL_TO_USR_LOCAL" = "1" ]; then
        local install_dir="/usr/local/lib/new_local_gpu_verifier"
    else
        local install_dir="$SCRIPT_DIR/new_local_gpu_verifier"
    fi

    # The first nvattest build needs Docker before the remaining step-3 tools.
    if { [ "$REBUILD_NVATTEST" = "1" ] || [ ! -x "$install_dir/nvattest" ]; } && ! command -v docker >/dev/null 2>&1; then
        install_docker || return 1
    fi
    sudo mkdir -p "$install_dir" || return 1
    sudo cp "$SCRIPT_DIR/utilities-build-nvattest-verifier.sh" "$install_dir/" || return 1
    sudo cp -r "$SCRIPT_DIR/nv_attest_gpu_verifier" "$install_dir/" || return 1

    # Create gpu-attestation command alias for easier usage
    if [ "$INSTALL_TO_USR_LOCAL" = "1" ] && [ "$CREATE_GPU_ATTESTATION_ALIAS" = "1" ]; then
        echo "Creating $GPU_ATTESTATION_CMD command ..."
        (echo '#!/usr/bin/env bash'
         echo 'set -o pipefail'
         declare -f gpu_preflight_checks thim_base_for_region detect_azure_region run_gpu_attestation
         echo 'run_gpu_attestation "$@"'
        ) | sudo tee "$GPU_ATTESTATION_CMD" >/dev/null || return 1
        sudo chmod +x "$GPU_ATTESTATION_CMD" || return 1
        echo "gpu-attestation command installed. Run 'sudo gpu-attestation' from anywhere."
    fi
    { [ "$REBUILD_NVATTEST" = "0" ] && [ -x "$install_dir/nvattest" ]; } || sudo bash "$install_dir/utilities-build-nvattest-verifier.sh" "$install_dir" || return 1
    NVATTEST_DIR="$install_dir" run_gpu_attestation
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
        if [ "${PIPESTATUS[0]}" -ne 0 ]; then
            exit 1
        fi
    fi
    if [ "$RUN_GPU" = "1" ]; then
        gpu_attestation "$@" 2>&1 | tee -a logs/current-operation.log | tee -a logs/all-operation.log
    fi
fi
