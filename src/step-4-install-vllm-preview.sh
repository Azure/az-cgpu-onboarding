#!/usr/bin/env bash

## [Optional] Install and launch a large language model (LLM) on an Azure Confidential GPU VM.
## Preview feature. Provided as sample onboarding guidance.
## Validated on:
##   Azure Confidential GPU VM
##   (Standard_NCC40ads_H100_v5)
## Example validated models:
##   phi4
##   deepseek
##   llama
##   qwen
## Model usage is subject to the applicable model provider license terms.
## Customers are responsible for obtaining any required permissions and
## accepting applicable licenses before downloading model weights.
## This script downloads model weights from model provider repositories
## and does not redistribute third-party model weights.
##
## Supported models:
##   phi4      — Microsoft Phi-4                              (~30 GB download)
##   deepseek  — DeepSeek R1 Distill Llama 70B FP8           (~70 GB download)
##   llama     — Llama 3.3 70B Instruct FP8                  (~70 GB download)
##   qwen      — Qwen 2.5 72B Instruct FP8                   (~70 GB download)
##
## What this script does:
##   1. Installs a Python venv at /opt/vllm with vLLM and huggingface-hub
##   2. Downloads the selected model weights to /usr/local/lib/<model>/
##   3. Creates a `cgpu` CLI with subcommands: chat, serve, bench, throughput, logs, model
##   4. Registers a systemd service (vllm-<prefix>.service) that auto-starts on boot
##
## After installation you can interact with the model immediately:
##   cgpu chat                   — interactive chat session
##   sudo cgpu serve             — start the vLLM OpenAI-compatible server (foreground; needs sudo)
##   curl http://localhost:8000/v1/chat/completions ...
##
## Usage:
##   sudo bash step-4-install-vllm-preview.sh --model phi4
##   sudo bash step-4-install-vllm-preview.sh --model qwen
##   sudo bash step-4-install-vllm-preview.sh --model llama
##   sudo bash step-4-install-vllm-preview.sh --model deepseek
##   sudo bash step-4-install-vllm-preview.sh --model phi4 --api-key <key>   # [optional] require Authorization: Bearer <key>
##
## For full documentation see: docs/Confidential-GPU-H100-vLLM-Quickstart.md
##

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Argument parsing ─────────────────────────────────────────────────────────

MODEL_NAME=""
API_KEY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --model) MODEL_NAME="$2"; shift 2 ;;
        --api-key)
            if [ -n "${2:-}" ] && [ "${2#--}" = "${2:-}" ]; then API_KEY="$2"; shift 2
            else echo "No API key given."; exit 1; fi ;;
        -h|--help)
            sed -n '/^##/s/^## \{0,1\}//p' "$0"
            exit 0
            ;;
        *) echo "Unknown argument: $1"; echo "Usage: sudo bash $0 --model <phi4|deepseek|llama|qwen> [--api-key <key>]"; exit 1 ;;
    esac
done

if [ -z "$MODEL_NAME" ]; then
    echo "========================================================"
    echo "  Confidential GPU — Optional vLLM Installation (NCC)"
    echo "========================================================"
    echo ""
    echo "This step installs a large language model that runs entirely"
    echo "inside your Confidential GPU VM. No data leaves the TEE."
    echo ""
    echo "Available models:"
    echo "  phi4      Microsoft Phi-4 (~30 GB, faster download)"
    echo "  deepseek  DeepSeek R1 Distill Llama 70B FP8 (~70 GB)"
    echo "  llama     Llama 3.3 70B Instruct FP8 (~70 GB)"
    echo "  qwen      Qwen 2.5 72B Instruct FP8 (~70 GB)"
    echo ""
    echo "Usage: sudo bash $0 --model <model-name>"
    echo ""
    echo "Skipping vLLM Installation. You can run this script at any"
    echo "time to add vLLM capability to your CGPU VM."
    exit 0
fi

# ── Prerequisites check ───────────────────────────────────────────────────────

echo "========================================================"
echo "  CGPU vLLM Installation — model: $MODEL_NAME"
echo "========================================================"
echo ""

# Require root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run with sudo: sudo bash $0 --model $MODEL_NAME"
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
    apt-get install -y python3-venv python3-pip -q
fi

# Ensure jq is available. The chat/bench CLI helpers build and parse JSON with jq.
# On Ubuntu 22.04 jq is not installed by default (24.04 ships it), so install it
# explicitly here to avoid "jq: command not found" at runtime.
if ! command -v jq &>/dev/null; then
    echo "Installing jq (required by the chat/bench CLI helpers)..."
    apt-get update -q && apt-get install -y jq -q
fi

# Disk space check — thresholds are model-specific:
#   phi4  ~30 GB weights + 20 GB overhead = 50 GB
#   70B FP8 models ~70 GB weights + 20 GB overhead = 90 GB
AVAILABLE_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
case "$MODEL_NAME" in
    phi4)     REQUIRED_GB=50 ;;
    *)        REQUIRED_GB=90 ;;
esac
if [ "$AVAILABLE_GB" -lt "$REQUIRED_GB" ]; then
    echo "WARNING: Only ${AVAILABLE_GB} GB free on /. Recommended minimum for ${MODEL_NAME} is ${REQUIRED_GB} GB."
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

echo "Running vLLM installer for model: $MODEL_NAME"
echo "(This will download model weights — may take 10–30 minutes on first run)"
echo ""

bash "$INSTALLER" --model "$MODEL_NAME" --install-to-service

# If an API key was provided, (re)start the model with bearer-token auth enabled
# for this session. The key is not written to persistent disk (see docs).
if [ -n "$API_KEY" ]; then
    echo ""
    echo "Enabling API-key authentication for this session..."
    cgpu model serve "$MODEL_NAME" --api-key "$API_KEY" || \
        echo "WARNING: could not start with the API key; run 'cgpu model serve $MODEL_NAME --api-key <key>' manually."
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
echo "  sudo cgpu serve              — start vLLM server in foreground (needs sudo)"
echo "  curl http://localhost:8000/v1/chat/completions   — OpenAI-compatible API"
echo ""
echo "Manage your model:"
echo "  cgpu model list              — show installed and available models"
echo "  cgpu model switch <name>     — replace with a different model"
echo "  cgpu model stop              — stop the running model"
echo "  cgpu logs                    — view service status and recent logs"
echo "  cgpu logs -f                 — follow live logs"
echo ""
echo "For full documentation see: docs/Confidential-GPU-H100-vLLM-Quickstart.md"
echo ""
