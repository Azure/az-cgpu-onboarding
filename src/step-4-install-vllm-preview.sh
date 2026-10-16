#!/usr/bin/env bash

## [Optional] Install and launch a large language model (LLM) on an Azure Confidential GPU VM.
## Preview feature. Provided as sample onboarding guidance.
## Validated on:
##   Azure Confidential GPU VM
##   (Standard_NCC40ads_H100_v5)
##
## Model selection:
## --model-id <organization>/<repository>
## Selects the Hugging Face repository directly. The model ID is normalized to lowercase and used as the canonical model identity.
##
## Examples:
## --model-id microsoft/phi-4
## --model-id qwen/qwen3.8-27b
##
## If MODEL_REVISION is not specified, the installer resolves and downloads
## the latest revision available on the selected repository's default branch
## at installation time.
##
## Model usage is subject to the applicable model provider license terms.
## Customers are responsible for obtaining any required permissions and
## accepting applicable licenses before downloading model weights.
## This script downloads model weights from model provider repositories
## and does not redistribute third-party model weights.
##
## What this script does:
##   1. Installs a Python venv at /opt/vllm with vLLM and huggingface-hub
##   2. Downloads the selected model weights to /usr/local/lib/<organization>/<repository>/
##   3. Creates a `cgpu` CLI with subcommands: chat, serve, bench, throughput, logs, model
##   4. Registers a model-specific systemd service that auto-starts on boot
##
## After installation you can interact with the model immediately:
##   cgpu chat                   — interactive chat session
##   sudo cgpu serve             — start the vLLM OpenAI-compatible server (foreground; needs sudo)
##   curl http://localhost:8000/v1/chat/completions ...
##
## Usage:
##   sudo bash step-4-install-vllm-preview.sh --model-id microsoft/phi-4
##   sudo bash step-4-install-vllm-preview.sh --model-id qwen/qwen3.8-27b
##   sudo bash step-4-install-vllm-preview.sh --model-id microsoft/phi-4 --api-key <key>   # [optional] require Authorization: Bearer <key>
##
## For full documentation see: docs/Confidential-GPU-H100-vLLM-Quickstart.md
##

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Runs an apt-related command with retry logic to handle transient package manager
# failures such as temporary repository, network, or lock issues.
# Retries up to 5 times with a 30-second delay between attempts.
apt_retry() {
    local max_attempts=5
    local delay_seconds=30
    local attempt=1

    while true; do
        echo "Running apt command (attempt ${attempt}/${max_attempts}): $*"

        if "$@"; then
            return 0
        fi

        if [ "$attempt" -ge "$max_attempts" ]; then
            echo "ERROR: apt command failed after ${max_attempts} attempts: $*" >&2
            return 1
        fi

        echo "apt command failed. Retrying in ${delay_seconds} seconds..."
        sleep "$delay_seconds"
        attempt=$((attempt + 1))
    done
}

# ── Argument parsing ─────────────────────────────────────────────────────────

MODEL_ID=""
API_KEY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --model-id)
            [[ $# -ge 2 ]] || { echo "Missing value for --model-id"; exit 1; }
            MODEL_ID="${2,,}"
            shift 2
            ;;
        --api-key)
            if [ -n "${2:-}" ] && [ "${2#--}" = "${2:-}" ]; then API_KEY="$2"; shift 2
            else echo "No API key given."; exit 1; fi ;;
        -h|--help)
            sed -n '/^##/s/^## \{0,1\}//p' "$0"
            exit 0
            ;;
        *) echo "Unknown argument: $1"; echo "Usage: sudo bash $0 --model-id <organization>/<repository> [--api-key <key>]"; exit 1 ;;
    esac
done

if [ -z "$MODEL_ID" ]; then
    echo "========================================================"
    echo "  Confidential GPU — Optional vLLM Installation (NCC)"
    echo "========================================================"
    echo ""
    echo "This step installs a large language model that runs entirely"
    echo "inside your Confidential GPU VM. No data leaves the TEE."
    echo ""
    echo "Usage:"
    echo "  Install by Hugging Face model ID:"
    echo "    sudo bash $0 --model-id <organization>/<repository>"
    echo ""
    echo "  Examples:"
    echo "    sudo bash $0 --model-id microsoft/phi-4"
    echo "    sudo bash $0 --model-id Qwen/Qwen3.8-27B"
    echo ""
    echo "Skipping vLLM Installation. You can run this script at any"
    echo "time to add vLLM capability to your CGPU VM."
    exit 0
fi

MODEL_DISPLAY="$MODEL_ID"

# ── Prerequisites check ───────────────────────────────────────────────────────

echo "========================================================"
echo "  CGPU vLLM Installation — model: $MODEL_DISPLAY"
echo "========================================================"
echo ""

# Require root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run with sudo: sudo bash $0 --model-id '$MODEL_ID'"
    exit 1
fi

# Require NVIDIA driver (step-1 must have completed)
if ! command -v nvidia-smi &>/dev/null || ! nvidia-smi &>/dev/null; then
    echo "ERROR: NVIDIA driver not found or GPU not accessible."
    echo "       Please complete step-1-install-gpu-driver.sh before running this step."
    exit 1
fi

# Require python3
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found. Please complete step-3-install-gpu-tools.sh first."
    exit 1
fi

# Ensure python3-venv is available (required for the vLLM virtual environment)
if ! python3 -c 'import ensurepip' &>/dev/null; then
    echo "Installing python3-venv (required for vLLM)..."
    apt_retry apt-get update -q
    apt_retry apt-get install -y --fix-missing python3-venv python3-pip -q
fi

# Ensure jq is available. The chat/bench CLI helpers build and parse JSON with jq.
# On Ubuntu 22.04 jq is not installed by default (24.04 ships it), so install it
# explicitly here to avoid "jq: command not found" at runtime.
if ! command -v jq &>/dev/null; then
    echo "Installing jq (required by the chat/bench CLI helpers)..."
    apt_retry apt-get update -q
    apt_retry apt-get install -y --fix-missing jq -q
fi

# Disk space check — thresholds are model-specific:
#   phi4  ~30 GB weights + 20 GB overhead = 50 GB
#   70B FP8 models ~70 GB weights + 20 GB overhead = 90 GB
AVAILABLE_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')

MODEL_REPO="${MODEL_ID##*/}"
if [[ "$MODEL_REPO" =~ [Pp]hi- ]]; then
    REQUIRED_GB=50
else
    REQUIRED_GB=90
fi

if [ "$AVAILABLE_GB" -lt "$REQUIRED_GB" ]; then
    echo "WARNING: Only ${AVAILABLE_GB} GB free on /. Recommended minimum for ${MODEL_DISPLAY} is ${REQUIRED_GB} GB."
    echo "         The installation may fail if disk space is exhausted during download."
    echo "         Press Ctrl+C to abort, or wait 10 seconds to continue..."
    sleep 10
fi

GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0)
echo "GPU VRAM detected: ${GPU_VRAM} MiB"
echo "Disk space available: ${AVAILABLE_GB} GB"
echo ""

# ── Delegate to the vLLM installer utility ────────────────────────────────────

INSTALLER="${SCRIPT_DIR}/utilities-launch-vllm.sh"

if [ ! -f "$INSTALLER" ]; then
    echo "ERROR: utilities-launch-vllm.sh not found in ${SCRIPT_DIR}."
    echo "       Please ensure you have the full CGPU onboarding package."
    exit 1
fi

echo "Running vLLM installer for Hugging Face model ID: $MODEL_ID"
echo "(This will download model weights — may take 10–30 minutes on first run)"

bash "$INSTALLER" --model-id "$MODEL_ID" --install-to-service

if ! /opt/vllm/bin/python3 -c 'import vllm' >/dev/null 2>&1; then
    echo "ERROR: vLLM installation verification failed."
    echo "       /opt/vllm/bin/python3 cannot import vllm."
    exit 1
fi


# Start the installed model as a background vLLM server.
# Do not automatically launch cgpu chat; users can start an interactive chat session separately with `cgpu chat`.
echo ""
echo "Starting serve $MODEL_ID..."

if [ -n "$API_KEY" ]; then
    # If an API key was provided, (re)start the model with bearer-token auth enabled
    # for this session. The key is not written to persistent disk (see docs).
    echo "Enabling API-key authentication for this session..."

    cgpu serve "$MODEL_ID" --daemon --api-key "$API_KEY" || \
        echo "WARNING: could not start $MODEL_ID with the API key; run 'cgpu model serve $MODEL_ID --api-key <key>' manually."
else
    cgpu serve "$MODEL_ID" --daemon || \
        echo "WARNING: could not start $MODEL_ID; run 'cgpu model serve $MODEL_ID' manually."
fi

# ── Post-install summary ──────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  vLLM Installation complete!"
echo "========================================================"
echo ""
echo "Your model is running as a systemd service and will auto-start on reboot."
echo ""
echo "Quick start:"
echo "  cgpu chat                    — interactive chat in your terminal"
echo "  cgpu model serve --stop      — stop the model from being served"
echo "  curl http://localhost:8000/v1/chat/completions   — OpenAI-compatible API"
echo ""
echo "Manage your model:"
echo "  cgpu model list              — show installed and available models"
echo "  cgpu model switch <model-id> — replace with a different model"
echo "  cgpu model stop              — stop the running model"
echo "  cgpu logs                    — view service status and recent logs"
echo "  cgpu logs -f                 — follow live logs"
echo ""
echo "For full documentation see: docs/Confidential-GPU-H100-vLLM-Quickstart.md"
echo ""

