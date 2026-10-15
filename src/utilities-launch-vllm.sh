#!/bin/bash
# ----------------------------------------------------------------------------
# Multi-model vLLM installer + launcher utility
#
# Usage:
#   1) Recommended: deploy using a specific Hugging Face Model ID:
#   sudo bash utilities-launch-vllm.sh --model-id microsoft/phi-4 --install-to-service
#   sudo bash utilities-launch-vllm.sh --model-id qwen/qwen3.8-27b --install-to-service
#
#   --model-id is normalized to lowercase and kept as the canonical model identity.
#   The installer derives the supported runtime family and resolves the latest revision on
#   the repository's default branch at installation time unless MODEL_REVISION is set.
#
# Example validated Hugging Face Model IDs (--model-id):
#   phi4:
#     - microsoft/phi-4
#   qwen:
#     - qwen/qwen3.8-27b
#     - redhatai/qwen2.5-72b-instruct-fp8-dynamic
#   llama:
#     - redhatai/llama-3.3-70b-instruct-fp8-dynamic
#   deepseek:
#     - redhatai/deepseek-r1-distill-llama-70b-fp8-dynamic
#
# Note:
#   Ensure sufficient disk space prior to execution, as large models (70B+) require substantial local storage.
# ----------------------------------------------------------------------------

set -euo pipefail

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

    echo "apt command failed. Retrying in ${delay_seconds}s..."
    sleep "$delay_seconds"
    attempt=$((attempt + 1))
  done
}

DRY_RUN=false
VENV_DIR="/opt/vllm"
INSTALL_DIR="/usr/local/bin"
# Backing scripts for the `cgpu` subcommands live here; users invoke them via the
# single `cgpu` dispatcher installed into INSTALL_DIR (e.g. `cgpu chat`, `cgpu serve`).
CLI_DIR="/usr/local/lib/cgpu-cli"
INSTALL_SERVICE=false
SKIP_PREWARM=false
MODEL_ID=""
CACHE_ROOT="/var/cache/vllm-compile"
CACHE_KEY=""
COMPILE_CACHE_DIR=""
INDUCTOR_CACHE_DIR=""
# Pin vllm to the last known-good version (0.20.0 broke FP8 Distill-Llama init
# on driver 590 / CUDA 13.1; 0.19.1 was the version baked into the green
# qwen2.5-72b VMI). Override via VLLM_VERSION env var if needed.
VLLM_VERSION="${VLLM_VERSION:-0.19.1}"
ATTN_BACKEND=""
GDN_PREFILL_BACKEND=""

# Parse CLI arguments. Walks $@ one token at a time:
#   --model-id <org/repo>   consume 2 tokens; set MODEL_ID (e.g., microsoft/phi-4)
#   --install-to-service    boolean flag; create + enable the systemd unit
#   --skip-prewarm          boolean flag; skip the bake-time CUDA cache pre-warm
#                           (used by `cgpu model switch` at runtime; pipeline omits it)
#   --dry-run               boolean flag; validate logic without executing downloads
# Anything else aborts with a non-zero exit so typos don't silently no-op.
while [ $# -gt 0 ]; do
  case "$1" in
    --model-id)
      [ $# -ge 2 ] || { echo "Missing value for --model-id"; exit 1; }
      MODEL_ID="${2,,}"
      shift 2
      ;;
    --install-to-service) INSTALL_SERVICE=true; shift ;;
    --skip-prewarm) SKIP_PREWARM=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [ -z "$MODEL_ID" ]; then
  echo "Usage:"
  echo "  $0 --model-id <model-id from huggingface-repo> [--install-to-service]"
  exit 1
fi

# Validate the canonical model ID and derive its internal runtime family.
if [[ ! "$MODEL_ID" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "Invalid Hugging Face model ID: $MODEL_ID"
  echo "Expected format: <organization-or-user>/<repository>"
  exit 1
fi

MODEL_REPO="${MODEL_ID##*/}"
DERIVED_MODEL_NAME=""

# DeepSeek must be checked before Llama because its repo name can also contain Llama.
if [[ "$MODEL_REPO" =~ [Dd]eep[Ss]eek- ]]; then
  DERIVED_MODEL_NAME="deepseek"
elif [[ "$MODEL_REPO" =~ [Ll]lama- ]]; then
  DERIVED_MODEL_NAME="llama"
elif [[ "$MODEL_REPO" =~ [Qq]wen ]]; then
  DERIVED_MODEL_NAME="qwen"
elif [[ "$MODEL_REPO" =~ [Pp]hi- ]]; then
  DERIVED_MODEL_NAME="phi4"
else
  echo "Unable to determine a supported runtime profile from model ID: $MODEL_ID"
  exit 1
fi

MODEL_NAME="$DERIVED_MODEL_NAME"
echo "Using Hugging Face model ID: $MODEL_ID"
echo "Resolved runtime profile: $MODEL_NAME"


# Runtime profile derived from MODEL_ID. MODEL_NAME is internal only; the full
# lowercased MODEL_ID remains the canonical identity used by storage and the CLI.
case "$MODEL_NAME" in
  phi4)
    PORT=8000
    SERVE_ARGS="--max-model-len 16384 --trust-remote-code"
    SYS_PROMPT="You are Phi-4, a helpful AI assistant. Answer concisely and accurately."
    ;;
  deepseek)
    PORT=8000
    SERVE_ARGS="--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code"
    SYS_PROMPT=""
    ;;
  llama)
    PORT=8000
    SERVE_ARGS="--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code"
    SYS_PROMPT="You are a helpful, respectful and honest assistant."
    ;;
  qwen)
    PORT=8000
    SERVE_ARGS="--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code"
    SYS_PROMPT="You are Qwen, a helpful AI assistant created by Alibaba Cloud."
    ;;
esac


# Keep the complete lowercased model ID as the canonical on-disk identity.
MODEL_REPO="${MODEL_ID##*/}"
MODEL_DIR="/usr/local/lib/${MODEL_ID}"
DISPLAY_NAME="$MODEL_ID"
CACHE_KEY="${MODEL_ID//\//--}"
PREFIX="$CACHE_KEY"

if [[ "$MODEL_REPO" =~ ([0-9]+([.][0-9]+)?b) ]]; then
  MODEL_SIZE="${BASH_REMATCH[1]}"
else
  MODEL_SIZE="unknown"
fi

# Qwen3.5+ hybrid GDN models may use FlashInfer GDN JIT, which requires nvcc.
# NCC images do not install the CUDA toolkit compiler, so use Triton for these IDs.
if [ "$MODEL_NAME" = "qwen" ]; then
  MODEL_REPO="${MODEL_ID##*/}"
  if [[ "$MODEL_REPO" =~ ^qwen3\.(5|6|7|8|9)- ]]; then
    GDN_PREFILL_BACKEND="triton"
  fi
fi

if [ -n "$GDN_PREFILL_BACKEND" ]; then
  SERVE_ARGS="${SERVE_ARGS} --gdn-prefill-backend ${GDN_PREFILL_BACKEND}"
  echo "Using GDN prefill backend: ${GDN_PREFILL_BACKEND}"
fi

# Defensive fallback: if model config did not set an explicit backend and
# nvcc is unavailable, avoid FlashInfer JIT paths that require CUDA toolkit.
if [ -z "$ATTN_BACKEND" ]; then
  if ! command -v nvcc >/dev/null 2>&1 && [ ! -x /usr/local/cuda/bin/nvcc ]; then
    ATTN_BACKEND="FLASH_ATTN"
    echo "nvcc not found; forcing VLLM_ATTENTION_BACKEND=${ATTN_BACKEND}."
  fi
fi

echo "Pinned vllm=${VLLM_VERSION} (override with VLLM_VERSION env var)."

# Set per-model cache directories so models don't share/corrupt each other's cache
COMPILE_CACHE_DIR="${CACHE_ROOT}/${CACHE_KEY}"
INDUCTOR_CACHE_DIR="${CACHE_ROOT}/${CACHE_KEY}/inductor"

# Append compilation-config now that COMPILE_CACHE_DIR is known
SERVE_ARGS="${SERVE_ARGS} --compilation-config '{\"cache_dir\":\"${COMPILE_CACHE_DIR}\"}'"

# ============================== DRY RUN ==============================
if [ "$DRY_RUN" = true ]; then
    echo "=== Dry Run ==="
    echo "MODEL_ID=$MODEL_ID"
    echo "MODEL_NAME=$MODEL_NAME"
    echo "MODEL_DIR=$MODEL_DIR"
    echo "DISPLAY_NAME=$DISPLAY_NAME"
    echo "MODEL_SIZE=$MODEL_SIZE"
    echo "PREFIX=$PREFIX"
    echo "COMPILE_CACHE_DIR=$COMPILE_CACHE_DIR"
    echo "INDUCTOR_CACHE_DIR=$INDUCTOR_CACHE_DIR"
    echo "SERVE_ARGS=$SERVE_ARGS"
    echo "GDN_PREFILL_BACKEND=$GDN_PREFILL_BACKEND"
    exit 0
fi

echo "============================================"
echo "  ${DISPLAY_NAME} CGPU Installer"
echo "============================================"

# Clean up any existing vllm services that don't match current model
# This prevents stale service files from carrying over into the VMI
for svc in /etc/systemd/system/vllm-*.service; do
    [ -f "$svc" ] || continue
    svc_name=$(basename "$svc")
    if [ "$svc_name" != "vllm-${PREFIX}.service" ]; then
        echo "Stopping other model service: $svc_name"
        systemctl stop "$svc_name" 2>/dev/null || true
        systemctl disable "$svc_name" 2>/dev/null || true
    fi
done

systemctl daemon-reload 2>/dev/null || true

# Persist this script so 'cgpu model switch' works after deprovision
cp "$(realpath "$0")" /usr/local/lib/utilities-launch-vllm.sh 2>/dev/null || true
chmod +x /usr/local/lib/utilities-launch-vllm.sh 2>/dev/null || true

# Create persistent compile cache directories
echo "[0/6] Setting up vLLM compile cache at ${COMPILE_CACHE_DIR}..."
mkdir -p "${COMPILE_CACHE_DIR}"
mkdir -p "${INDUCTOR_CACHE_DIR}"
chmod -R 755 "${COMPILE_CACHE_DIR}"
mkdir -p "${COMPILE_CACHE_DIR}/torch_aot"
mkdir -p "${COMPILE_CACHE_DIR}/triton"

# Pre-create symlink so AOT cache saves correctly during pre-warm
mkdir -p /root/.cache/vllm
ln -sfn "${COMPILE_CACHE_DIR}/torch_aot" /root/.cache/vllm/torch_compile_cache
echo "  Symlink: /root/.cache/vllm/torch_compile_cache -> ${COMPILE_CACHE_DIR}/torch_aot"

# Pre-reads all model weights into RAM page cache before vLLM starts.
# On first boot from VMI, disk reads go through blob storage at ~47 MB/s.
# Pre-reading forces all blocks into RAM so vLLM reads at RAM speed (~19 GB/s).
cat > /usr/local/bin/vllm-warm-cache << 'WARMEOF'
#!/bin/bash
set -euo pipefail

MODEL_DIR="${1:-}"
INDUCTOR_DIR="${2:-}"
TRITON_DIR="${3:-}"

if [ -z "$MODEL_DIR" ] || [ -z "$INDUCTOR_DIR" ] || [ -z "$TRITON_DIR" ]; then
    echo "Usage: vllm-warm-cache <model-dir> <inductor-cache-dir> <triton-cache-dir>"
    exit 1
fi

export TORCHINDUCTOR_CACHE_DIR="$INDUCTOR_DIR"
export TRITON_CACHE_DIR="$TRITON_DIR"

first_shard=$(find "$MODEL_DIR" -name "*.safetensors" 2>/dev/null | sort | head -1)
if [ -z "$first_shard" ]; then
    echo "No safetensors found, skipping cache warm."
    exit 0
fi

# Measure disk read speed by reading 256MB from the first shard
speed_mb=$(dd if="$first_shard" of=/dev/null bs=4M count=64 2>&1 | grep -oP '[\d.]+ [GM]B/s' || echo "0 MB/s")
speed_num=$(echo "$speed_mb" | grep -oP '[\d.]+' | head -1)
is_gb=0
echo "$speed_mb" | grep -q 'GB/s' && is_gb=1

# Normalize to MB/s (convert GB/s to MB/s if needed)
if [ "$is_gb" -gt 0 ]; then
    speed_mbs=$(awk "BEGIN{printf \"%.0f\", $speed_num * 1024}")
else
    speed_mbs=$(awk "BEGIN{printf \"%.0f\", $speed_num}")
fi

# Skip warmup if disk is already hydrated (> 100 MB/s).
# This covers second boot (hydrated SSD ~150 MB/s) AND RAM cache (~19 GB/s).
# Cold snapshot redirect is 26-50 MB/s, so 100 MB/s is a safe threshold.
if awk "BEGIN{exit !($speed_mbs > 100)}"; then
    echo "Host cache warm (${speed_mb}) - skipping warmup."
    exit 0
fi

echo "Host cache cold (${speed_mb:-unknown}) - warming cache..."
WARM_T0=$(date +%s)
find "$MODEL_DIR" -name "*.safetensors" -print0 | xargs -0 -P8 -r -I{} dd if={} of=/dev/null bs=4M 2>/dev/null
WARM_ELAPSED=$(( $(date +%s) - WARM_T0 ))
echo "Prefetch complete in ${WARM_ELAPSED}s."
WARMEOF
chmod +x /usr/local/bin/vllm-warm-cache

# venv + vllm
echo "[1/6] Setting up Python venv + vLLM..."
# Ubuntu's system Python does not ship the venv/ensurepip module by default
# (e.g. Ubuntu 24.04 / Python 3.12), so `python3 -m venv` fails with
# "ensurepip is not available". Install the matching python3-venv package first.
PYTHON_BIN="${PYTHON_BIN:-python3}"
PY_VER="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
VENV_PACKAGE="python${PY_VER}-venv"

echo "Using $("$PYTHON_BIN" --version 2>&1); installing ${VENV_PACKAGE}..."

# sometimes, we get 502, so here we retry apt just in case.
apt_retry apt-get -o DPkg::Lock::Timeout=300 update

if ! apt_retry apt-get -o DPkg::Lock::Timeout=300 install -y --fix-missing "$VENV_PACKAGE"; then
    echo "Package ${VENV_PACKAGE} unavailable; trying python3-venv..."
    apt_retry apt-get -o DPkg::Lock::Timeout=300 install -y --fix-missing python3-venv
fi

if ! "$PYTHON_BIN" -m ensurepip --version >/dev/null 2>&1; then
    echo "ERROR: ensurepip is still unavailable for $("$PYTHON_BIN" --version 2>&1)."
    echo "Expected package: ${VENV_PACKAGE}"
    exit 1
fi

if [ ! -x "$VENV_DIR/bin/python3" ]; then
    echo "Creating vLLM Python environment..."
    "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python3" -m pip install --upgrade pip "setuptools>=77.0.3,<81.0.0" wheel -q

# Pin vllm to last known-good version (0.20.0 broke FP8 Distill-Llama init on
# driver 590 / CUDA 13.1; 0.19.1 was the version baked into the green
# qwen2.5-72b VMI). Override via VLLM_VERSION env var if needed.
INSTALLED_VLLM_VERSION=$("$VENV_DIR/bin/python3" -c 'import vllm; print(vllm.__version__)' 2>/dev/null || true)

if [ "$INSTALLED_VLLM_VERSION" != "$VLLM_VERSION" ]; then
    echo "Installing vLLM ${VLLM_VERSION}..."
    "$VENV_DIR/bin/python3" -m pip install "vllm==${VLLM_VERSION}" huggingface-hub -q
else
    echo "vLLM ${VLLM_VERSION} already installed in ${VENV_DIR}."
    "$VENV_DIR/bin/python3" -m pip install huggingface-hub -q
fi

if ! "$VENV_DIR/bin/python3" -c 'import vllm' >/dev/null 2>&1; then
    echo "ERROR: vLLM was not installed correctly into ${VENV_DIR}."
    exit 1
fi

echo "Installed vLLM version: $("$VENV_DIR/bin/python3" -c 'import vllm; print(vllm.__version__)')"


# model weights
# Resolve the configured Hugging Face repository's current default-branch commit
# to an immutable SHA, then download that exact revision. This gives each build
# the latest available weights while keeping the resulting VMI reproducible and
# traceable. Set MODEL_REVISION explicitly to override/pin a specific revision.
echo "[2/6] Resolving latest ${DISPLAY_NAME} model revision..."
mkdir -p "$MODEL_DIR"

if [ -z "${MODEL_REVISION:-}" ]; then
    MODEL_REVISION=$("$VENV_DIR/bin/python3" - "$MODEL_ID" <<'PYEOF'
import sys
from huggingface_hub import HfApi

repo_id = sys.argv[1]
info = HfApi().model_info(repo_id=repo_id)
if not info.sha:
    raise SystemExit(f"Unable to resolve latest revision for {repo_id}")
print(info.sha)
PYEOF
    )
else
    echo "  MODEL_REVISION override supplied; skipping latest-revision lookup."
fi

if [ -z "$MODEL_REVISION" ]; then
    echo "ERROR: Unable to resolve model revision for ${MODEL_ID}."
    exit 1
fi

echo "  Model repo:      ${MODEL_ID}"
echo "  Model revision:  ${MODEL_REVISION}"
echo "[2/6] Downloading ${DISPLAY_NAME} model weights..."

DOWNLOAD_T0=$(date +%s)
"$VENV_DIR/bin/python3" - "$MODEL_ID" "$MODEL_DIR" "$MODEL_REVISION" <<'PYEOF'
import sys
from huggingface_hub import snapshot_download

repo_id, local_dir, revision = sys.argv[1:4]
snapshot_download(
    repo_id=repo_id,
    revision=revision,
    local_dir=local_dir,
    ignore_patterns=["*.gguf"],
)
PYEOF
DOWNLOAD_ELAPSED=$(( $(date +%s) - DOWNLOAD_T0 ))
MODEL_SIZE_ON_DISK=$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1 || echo unknown)

cat > "${MODEL_DIR}/.cgpu-model-version" <<EOF
MODEL_ID=${MODEL_ID}
MODEL_REVISION=${MODEL_REVISION}
DOWNLOADED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo "  Download complete in ${DOWNLOAD_ELAPSED}s (${MODEL_SIZE_ON_DISK} on disk)."
echo "  Pinned revision: ${MODEL_REVISION}"
#deactivate

# serve
echo "[3/6] Creating cgpu serve command..."
mkdir -p "${CLI_DIR}"
cat > "${CLI_DIR}/serve" << 'SERVEEOF'
#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "cgpu serve must be run as root (it writes to /var/log and /var/run)."
  echo "Re-run with sudo."
  echo "For normal use prefer: cgpu model serve <model-id>"
  exit 1
fi

PORT=8000
MODEL_ID=""
DAEMON=false
API_KEY=""
ACTION="start"

while [ $# -gt 0 ]; do
  case "$1" in
    --stop) ACTION="stop"; shift ;;
    --status) ACTION="status"; shift ;;
    --daemon) DAEMON=true; shift ;;
    --api-key)
      if [ -n "${2:-}" ] && [ "${2#--}" = "${2:-}" ]; then
        API_KEY="$2"
        shift 2
      else
        echo "No API key given."
        exit 1
      fi
      ;;
    -h|--help)
      echo "Usage: sudo cgpu serve <model-id> [--daemon] [--api-key <key>]"
      echo "       sudo cgpu serve --stop"
      echo "       sudo cgpu serve --status"
      exit 0
      ;;
    *)
      if [ -n "$MODEL_ID" ]; then
        echo "Unexpected argument: $1"
        exit 1
      fi
      MODEL_ID="${1,,}"
      shift
      ;;
  esac
done

model_id_from_dir() {
  local d="$1"
  local version_file="$d/.cgpu-model-version"
  [ -f "$version_file" ] || { echo ""; return; }
  sed -n 's/^MODEL_ID=//p' "$version_file" | head -1 | tr '[:upper:]' '[:lower:]'
}

find_model_dir() {
  local target="${1,,}"
  local target_dir="/usr/local/lib/${target}"
  local installed_model_id

  [ -f "$target_dir/.cgpu-model-version" ] || { echo ""; return; }
  installed_model_id=$(model_id_from_dir "$target_dir")
  [ "$installed_model_id" = "$target" ] || { echo ""; return; }
  echo "$target_dir"
}

resolve_model_id_from_service() {
  local svc="$1"
  local version_file candidate_id candidate_svc

  for version_file in /usr/local/lib/*/*/.cgpu-model-version; do
    [ -f "$version_file" ] || continue
    candidate_id=$(sed -n 's/^MODEL_ID=//p' "$version_file" | head -1 | tr '[:upper:]' '[:lower:]')
    [ -n "$candidate_id" ] || continue
    candidate_svc="vllm-${candidate_id//\//--}.service"
    if [ "$candidate_svc" = "$svc" ]; then
      echo "$candidate_id"
      return
    fi
  done

  echo ""
}

if [ "$ACTION" = "status" ]; then
  found=0

  if [ -n "$MODEL_ID" ]; then
    pidfile="/var/run/${MODEL_ID//\//--}-serve.pid"

    if [ -f "$pidfile" ]; then
      pid=$(cat "$pidfile" 2>/dev/null || true)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "$MODEL_ID is serving as a manual vLLM process."
        echo "PID: $pid"
        echo "API: http://localhost:$PORT/v1"
        found=1
      else
        echo "Stale PID file: $pidfile"
      fi
    fi

    svc_name="vllm-${MODEL_ID//\//--}.service"
    if systemctl is-active "$svc_name" > /dev/null 2>&1; then
      echo "$MODEL_ID is serving via systemd."
      echo "Service: $svc_name"
      echo "API: http://localhost:$PORT/v1"
      found=1
    fi

    if [ "$found" -eq 0 ]; then
      echo "$MODEL_ID is not running."
    fi

    exit 0
  fi

  for pidfile in /var/run/*-serve.pid; do
    [ -f "$pidfile" ] || continue
    pid=$(cat "$pidfile" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "Manual vLLM process: $(basename "$pidfile" -serve.pid)"
      echo "PID: $pid"
      found=1
    else
      echo "Stale PID file: $pidfile"
    fi
  done

  for svc in /etc/systemd/system/vllm-*.service; do
    [ -f "$svc" ] || continue
    svc_name=$(basename "$svc")
    if systemctl is-active "$svc_name" > /dev/null 2>&1; then
      echo "Systemd vLLM service: $svc_name"
      found=1
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "No vLLM server is running."
  fi

  exit 0
fi

if [ "$ACTION" = "stop" ]; then
  found=0

  if [ -n "$MODEL_ID" ]; then
    pidfile="/var/run/${MODEL_ID//\//--}-serve.pid"

    if [ -f "$pidfile" ]; then
      pid=$(cat "$pidfile" 2>/dev/null || true)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
      fi
      rm -f "$pidfile"
      echo "Stopped manual vLLM server for $MODEL_ID."
      found=1
    fi

    if [ "$found" -eq 1 ]; then
      exit 0
    fi

    svc_name="vllm-${MODEL_ID//\//--}.service"
    if systemctl is-active "$svc_name" > /dev/null 2>&1; then
      echo "$MODEL_ID is serving via systemd."
      echo "Stop it with: cgpu model stop"
      exit 1
    fi

    echo "$MODEL_ID is not running."
    exit 0
  fi

  for pidfile in /var/run/*-serve.pid; do
    [ -f "$pidfile" ] || continue
    pid=$(cat "$pidfile" 2>/dev/null || true)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    rm -f "$pidfile"
    found=1
  done

  if [ "$found" -eq 1 ]; then
    echo "Stopped manual vLLM server."
    exit 0
  fi

  for svc in /etc/systemd/system/vllm-*.service; do
    [ -f "$svc" ] || continue
    svc_name=$(basename "$svc")
    if systemctl is-active "$svc_name" > /dev/null 2>&1; then
      echo "A model is serving via systemd."
      echo "Service: $svc_name"
      echo "Stop it with: cgpu model stop"
      exit 1
    fi
  done

  echo "No manual vLLM server is running."
  exit 0
fi

if [ -z "$MODEL_ID" ]; then
  active_svc=""
  for svc in /etc/systemd/system/vllm-*.service; do
    [ -f "$svc" ] || continue
    svc_name=$(basename "$svc")
    if systemctl is-active "$svc_name" >/dev/null 2>&1; then
      active_svc="$svc_name"
      break
    fi
  done

  if [ -n "$active_svc" ]; then
    MODEL_ID=$(resolve_model_id_from_service "$active_svc")
  fi
fi

if [ -z "$MODEL_ID" ]; then
  echo "Usage: sudo cgpu serve <model-id> [--daemon] [--api-key <key>]"
  echo "For normal use prefer: cgpu model serve <model-id>"
  exit 1
fi

if [[ ! "$MODEL_ID" =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ ]]; then
  echo "Invalid Hugging Face model ID: $MODEL_ID"
  exit 1
fi

MODEL=$(find_model_dir "$MODEL_ID")
if [ -z "$MODEL" ] || [ ! -d "$MODEL" ]; then
  echo "Model $MODEL_ID is not installed."
  echo "Install/start it with: cgpu model serve $MODEL_ID"
  exit 1
fi

if curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
  echo "Port $PORT is already serving a model."
  echo ""

  active_svc=""
  for svc in /etc/systemd/system/vllm-*.service; do
    [ -f "$svc" ] || continue
    svc_name=$(basename "$svc")

    if systemctl is-active "$svc_name" >/dev/null 2>&1; then
      active_svc="$svc_name"
      break
    fi
  done

  if [ -n "$active_svc" ]; then
    echo "The existing model is served via systemd."
    echo "Stop it with:"
    echo "  cgpu model stop"
    exit 1
  fi

  manual_running=false
  for pidfile in /var/run/*-serve.pid; do
    [ -f "$pidfile" ] || continue

    pid=$(cat "$pidfile" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      manual_running=true
      break
    fi
  done

  if [ "$manual_running" = true ]; then
    echo "The existing model is served via sudo cgpu serve."
    echo "Stop it with:"
    echo "  sudo cgpu serve --stop"
  else
    echo "A vLLM server is already running, but it is not managed by a known cgpu service."
    echo "Check the running process before starting another model."
  fi

  exit 1
fi

MODEL_REPO="${MODEL_ID##*/}"
PREFIX="${MODEL_ID//\//--}"
COMPILE_CACHE_DIR="/var/cache/vllm-compile/${PREFIX}"
INDUCTOR_CACHE_DIR="${COMPILE_CACHE_DIR}/inductor"
LOG="/var/log/${PREFIX}"
PID="/var/run/${PREFIX}-serve.pid"
SERVE_ARGS=()

if [[ "$MODEL_REPO" =~ [Dd]eep[Ss]eek- ]]; then
  SERVE_ARGS+=(--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code)
elif [[ "$MODEL_REPO" =~ [Ll]lama- ]]; then
  SERVE_ARGS+=(--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code)
elif [[ "$MODEL_REPO" =~ [Qq]wen ]]; then
  SERVE_ARGS+=(--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code)
elif [[ "$MODEL_REPO" =~ [Pp]hi- ]]; then
  SERVE_ARGS+=(--max-model-len 16384 --trust-remote-code)
else
  echo "Unable to determine a supported runtime profile from model ID: $MODEL_ID"
  exit 1
fi

if [[ "$MODEL_REPO" =~ ^qwen3\.(5|6|7|8|9)- ]]; then
  SERVE_ARGS+=(--gdn-prefill-backend triton)
fi

SERVE_ARGS+=(--compilation-config "{\"cache_dir\":\"${COMPILE_CACHE_DIR}\"}")

if ! command -v nvcc >/dev/null 2>&1 && [ ! -x /usr/local/cuda/bin/nvcc ]; then
  export VLLM_ATTENTION_BACKEND=FLASH_ATTN
fi

export TORCHINDUCTOR_CACHE_DIR="$INDUCTOR_CACHE_DIR"
export TRITON_CACHE_DIR="${COMPILE_CACHE_DIR}/triton"
[ -n "$API_KEY" ] && export VLLM_API_KEY="$API_KEY"

mkdir -p "$LOG" "$INDUCTOR_CACHE_DIR" "${COMPILE_CACHE_DIR}/torch_aot" "${COMPILE_CACHE_DIR}/triton" /root/.cache/vllm
ln -sfn "${COMPILE_CACHE_DIR}/torch_aot" /root/.cache/vllm/torch_compile_cache 2>/dev/null || true

if [ "$DAEMON" = true ]; then
  nohup /opt/vllm/bin/python3 -m vllm.entrypoints.openai.api_server \
    --model "$MODEL" --host 0.0.0.0 --port "$PORT" \
    "${SERVE_ARGS[@]}" > "$LOG/serve.log" 2>&1 &
  echo $! > "$PID"
  echo -n "Waiting for model to load "
  for i in $(seq 1 600); do
    curl -s "http://localhost:$PORT/health" > /dev/null 2>&1 && echo " Ready" && exit 0
    if ! kill -0 "$(cat "$PID")" 2>/dev/null; then
      echo " Failed -- check $LOG/serve.log"
      exit 1
    fi
    echo -n "."
    sleep 1
  done
  echo " Timeout -- check $LOG/serve.log"
  exit 1
else
  exec /opt/vllm/bin/python3 -m vllm.entrypoints.openai.api_server \
    --model "$MODEL" --host 0.0.0.0 --port "$PORT" \
    "${SERVE_ARGS[@]}"
fi
SERVEEOF
chmod +x "${CLI_DIR}/serve"

# chat
echo "[4/6] Creating cgpu chat command..."
cat > "${CLI_DIR}/chat" << 'CHATEOF'
#!/bin/bash
set -euo pipefail

PORT=8000
URL="http://localhost:$PORT/v1/chat/completions"

# Optional API key: --api-key <key> (a value is required; errors otherwise).
# Sent as 'Authorization: Bearer <key>'. Omit it if the server has no key set.
API_KEY=""
SYS_OVERRIDE=""
SYS_OVERRIDE_SET=false

while [ $# -gt 0 ]; do
  case "$1" in
    --system)
      if [ -n "${2:-}" ]; then
        SYS_OVERRIDE="$2"
        SYS_OVERRIDE_SET=true
        shift 2
      else
        echo "No system prompt given."
        exit 1
      fi
      ;;
    --api-key)
      if [ -n "${2:-}" ] && [ "${2#--}" = "${2:-}" ]; then
        API_KEY="$2"
        shift 2
      else
        echo "No API key given."
        exit 1
      fi
      ;;
    *) shift ;;
  esac
done

AUTH=()
[ -n "$API_KEY" ] && AUTH=(-H "Authorization: Bearer $API_KEY")

if ! curl -s "http://localhost:$PORT/health" > /dev/null 2>&1; then
  echo "No model is currently serving."
  echo "Start one with: cgpu model serve <model-id>"
  exit 1
fi

# Preflight auth check: /v1/models requires the API key if one is set.
CODE=$(curl -s -o /dev/null -w "%{http_code}" "${AUTH[@]}" "http://localhost:$PORT/v1/models" 2>/dev/null || echo 000)
if [ "$CODE" = "401" ]; then
  if [ -n "$API_KEY" ]; then
    echo "The API key was rejected (401). Check the key and retry: cgpu chat --api-key <key>"
  else
    echo "This server requires an API key. Re-run: cgpu chat --api-key <key>"
    echo "(or restart it without a key: cgpu model serve <model-id>)"
  fi
  exit 1
fi

MODEL=$(curl -sf "${AUTH[@]}" "http://localhost:$PORT/v1/models" | jq -r '.data[0].id // empty')
if [ -z "$MODEL" ]; then
  echo "Unable to determine the currently served model."
  exit 1
fi

DISPLAY_MODEL="$MODEL"
if [ -f "${MODEL}/.cgpu-model-version" ]; then
  MODEL_ID=$(sed -n 's/^MODEL_ID=//p' "${MODEL}/.cgpu-model-version" | head -1)
  [ -n "$MODEL_ID" ] && DISPLAY_MODEL="${MODEL_ID,,}"
fi

MODEL_REPO="${DISPLAY_MODEL##*/}"
SYS=""

if [[ "$MODEL_REPO" =~ [Dd]eep[Ss]eek- ]]; then
  SYS=""
elif [[ "$MODEL_REPO" =~ [Ll]lama- ]]; then
  SYS="You are a helpful, respectful and honest assistant."
elif [[ "$MODEL_REPO" =~ [Qq]wen ]]; then
  SYS="You are Qwen, a helpful AI assistant created by Alibaba Cloud."
elif [[ "$MODEL_REPO" =~ [Pp]hi- ]]; then
  SYS="You are Phi-4, a helpful AI assistant. Answer concisely and accurately."
fi

if [ "$SYS_OVERRIDE_SET" = true ]; then
  SYS="$SYS_OVERRIDE"
fi

echo "$DISPLAY_MODEL Chat -- /quit to exit, /clear to reset"

if [ -n "$SYS" ]; then
  MSGS=$(jq -n --arg s "$SYS" '[{"role":"system","content":$s}]')
else
  MSGS="[]"
fi

while echo -ne "\033[1;36mYou > \033[0m" && read -r INPUT; do
  case "$INPUT" in
    /quit|/q)
      exit 0
      ;;
    /clear)
      if [ -n "$SYS" ]; then
        MSGS=$(jq -n --arg s "$SYS" '[{"role":"system","content":$s}]')
      else
        MSGS="[]"
      fi
      continue
      ;;
    "")
      continue
      ;;
  esac

  MSGS=$(echo "$MSGS" | jq --arg m "$INPUT" '. + [{"role":"user","content":$m}]')

  if [ -n "$SYS" ]; then
    RESP=$(curl -s "$URL" -H "Content-Type: application/json" "${AUTH[@]}" \
      -d "$(jq -n --arg model "$MODEL" --argjson msgs "$MSGS" '{model:$model,messages:$msgs,max_tokens:2048,temperature:0.7,chat_template_kwargs:{enable_thinking:false}}')")
  else
    RESP=$(curl -s "$URL" -H "Content-Type: application/json" "${AUTH[@]}" \
      -d "$(jq -n --arg model "$MODEL" --argjson msgs "$MSGS" '{model:$model,messages:$msgs,max_tokens:2048,temperature:0.7}')")
  fi

  RAW_ANS=$(echo "$RESP" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
  [ -z "$RAW_ANS" ] && { echo "Error: $(echo "$RESP" | jq -r '(.error.message? // .error? // .message? // "unknown")' 2>/dev/null || echo "$RESP")"; continue; }

  ANS=$(python3 - "$RAW_ANS" << 'PYEOF'
import re
import sys

# GPT-2 byte-level BPE: map printable unicode chars back to raw bytes,
# then UTF-8 decode. Handles Ġ (space), Ċ (newline), and emoji bytes.
def _b2u():
    bs = list(range(ord("!"), ord("~") + 1)) + list(range(ord("¡"), ord("¬") + 1)) + list(range(ord("®"), ord("ÿ") + 1))
    cs = bs[:]
    n = 0
    for b in range(256):
        if b not in bs:
            bs.append(b)
            cs.append(256 + n)
            n += 1
    return dict(zip([chr(c) for c in cs], bs))

U2B = _b2u()

def decode_bpe(s):
    try:
        return bytes(U2B[c] for c in s).decode("utf-8", errors="replace")
    except KeyError:
        return s

text = sys.argv[1]
text = decode_bpe(text)
text = re.sub(r"<think>.*?</think>", "", text, flags=re.S)
text = text.replace("</think>", "")
text = re.sub(r"\n{3,}", "\n\n", text).strip()
print(text)
PYEOF
)

  echo -e "\033[1;32m$DISPLAY_MODEL > \033[0m$ANS\n"
  MSGS=$(echo "$MSGS" | jq --arg m "$ANS" '. + [{"role":"assistant","content":$m}]')
done
CHATEOF

chmod +x "${CLI_DIR}/chat"

# bench + throughput
echo "[5/6] Creating cgpu bench + cgpu throughput commands..."
cat > "${CLI_DIR}/bench" << 'BENCHEOF'
#!/bin/bash
set -euo pipefail

PORT=8000

# Optional API key: --api-key <key>. Sent as 'Authorization: Bearer <key>'.
API_KEY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --api-key)
      if [ -n "${2:-}" ] && [ "${2#--}" = "${2:-}" ]; then
        API_KEY="$2"
        shift 2
      else
        echo "No API key given."
        exit 1
      fi
      ;;
    *) shift ;;
  esac
done

AUTH=()
[ -n "$API_KEY" ] && AUTH=(-H "Authorization: Bearer $API_KEY")

if ! curl -s "http://localhost:$PORT/health" > /dev/null 2>&1; then
  echo "Server is not running. Start it with: cgpu model serve <model-id>"
  exit 1
fi

CODE=$(curl -s -o /dev/null -w "%{http_code}" "${AUTH[@]}" "http://localhost:$PORT/v1/models" 2>/dev/null || echo 000)

if [ "$CODE" = "401" ]; then
  echo "This server requires an API key. Re-run: cgpu bench --api-key <key>"
  exit 1
fi

MODEL=$(curl -sf "${AUTH[@]}" "http://localhost:$PORT/v1/models" | jq -r '.data[0].id // empty')

if [ -z "$MODEL" ]; then
  echo "Unable to determine the currently served model."
  exit 1
fi

START=$(date +%s%N)

RESP=$(curl -s "http://localhost:$PORT/v1/chat/completions" \
  -H "Content-Type: application/json" \
  "${AUTH[@]}" \
  -d "$(jq -n \
    --arg model "$MODEL" \
    '{
      model:$model,
      messages:[{
        role:"user",
        content:"Explain quantum entanglement in 3 sentences."
      }],
      max_tokens:256,
      temperature:0
    }')")

MS=$(( ($(date +%s%N) - START) / 1000000 ))

ANS=$(echo "$RESP" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

if [ -z "$ANS" ]; then
  echo "Error: $(echo "$RESP" | jq -r '(.error.message? // .error? // .message? // "unknown")' 2>/dev/null || echo "$RESP")"
  exit 1
fi

TOK=$(echo "$RESP" | jq -r '.usage.completion_tokens // "?"')

echo "$ANS"
echo "--- ${TOK} tokens in ${MS}ms"

[ "$TOK" != "?" ] && [ "$TOK" -gt 0 ] && \
  echo "    $(awk "BEGIN{printf \"%.1f\",$TOK/($MS/1000)}") tok/s"
BENCHEOF

chmod +x "${CLI_DIR}/bench"

cat > "${CLI_DIR}/throughput" << 'THROUGHPUTEOF'
#!/bin/bash
set -euo pipefail

PORT=8000
API_KEY=""
N=100
IL=128
OL=256
EXTRA=()

while [ $# -gt 0 ]; do
  case "$1" in
    --api-key)
      if [ -n "${2:-}" ] && [ "${2#--}" = "${2:-}" ]; then
        API_KEY="$2"
        shift 2
      else
        echo "No API key given."
        exit 1
      fi
      ;;
    -n)
      N="$2"
      shift 2
      ;;
    --input-len)
      IL="$2"
      shift 2
      ;;
    --output-len)
      OL="$2"
      shift 2
      ;;
    --request-rate)
      EXTRA+=("--request-rate" "$2")
      shift 2
      ;;
    -h|--help)
      echo "Usage: throughput [-n NUM] [--input-len N] [--output-len N] [--request-rate N] [--api-key <key>]"
      exit 0
      ;;
    *)
      EXTRA+=("$1")
      shift
      ;;
  esac
done

AUTH=()
HEADER_ARGS=()
if [ -n "$API_KEY" ]; then
  AUTH=(-H "Authorization: Bearer $API_KEY")
  HEADER_ARGS=(--header "Authorization=Bearer $API_KEY")
fi

if ! curl -s "http://localhost:$PORT/health" > /dev/null 2>&1; then
  echo "Server is not running. Start it with: cgpu model serve <model-id>"
  exit 1
fi

CODE=$(curl -s -o /dev/null -w "%{http_code}" "${AUTH[@]}" "http://localhost:$PORT/v1/models" 2>/dev/null || echo 000)
if [ "$CODE" = "401" ]; then
  echo "This server requires an API key. Re-run: cgpu throughput --api-key <key>"
  exit 1
fi

MODEL=$(curl -sf "${AUTH[@]}" "http://localhost:$PORT/v1/models" | jq -r '.data[0].id // empty')

if [ -z "$MODEL" ]; then
  echo "Unable to determine the currently served model."
  exit 1
fi

/opt/vllm/bin/vllm bench serve \
  --model "$MODEL" \
  --base-url "http://localhost:$PORT" \
  --endpoint /v1/completions \
  --dataset-name random \
  --num-prompts "$N" \
  --random-input-len "$IL" \
  --random-output-len "$OL" \
  "${EXTRA[@]}" \
  "${HEADER_ARGS[@]}"
THROUGHPUTEOF

chmod +x "${CLI_DIR}/throughput"

# cgpu dispatcher — single entrypoint that routes to the backing subcommand scripts
cat > "${INSTALL_DIR}/cgpu" << 'CGPUEOF'
#!/bin/bash
CLI_DIR="/usr/local/lib/cgpu-cli"
cmd="${1:-}"
case "$cmd" in
  chat|serve|bench|throughput|logs|model)
    if [ ! -x "$CLI_DIR/$cmd" ]; then
      echo "'cgpu $cmd' is not available (no model installed yet)."
      exit 1
    fi
    shift
    exec "$CLI_DIR/$cmd" "$@"
    ;;
  ""|-h|--help)
    echo "Usage: cgpu <command> [options]"
    echo ""
    echo "Commands:"
    echo "  chat [--system "..."] [--api-key <key>]       Interactive chat"
    echo "  serve <model-id> [--daemon|--stop|--status]     Low-level server (needs sudo)"
    echo "  bench [--api-key <key>]                         Single-request latency test"
    echo "  throughput [-n N] [--request-rate N] [--api-key <key>]  Multi-request load test"
    echo "  logs [-f|-e|-a]                                 View active service logs"
    echo "  model list|serve|stop|delete|switch <model-id>  Manage models"
    echo ""
    echo "API key (optional): pass --api-key <key> when serving or querying an authenticated session."
    ;;
  *)
    echo "Unknown command: $cmd"
    echo "Run 'cgpu' for usage."
    exit 1
    ;;
esac
CGPUEOF
chmod +x "${INSTALL_DIR}/cgpu"

# systemd service (only with --install-to-service)
echo "[6/6] Finalizing..."
if [ "$INSTALL_SERVICE" = true ]; then
    echo "Creating systemd service: vllm-${PREFIX}.service"

    GPU_COUNT=1
    PREWARM_WAIT_MINUTES=60
    if command -v nvidia-smi &> /dev/null; then
        GPU_COUNT=$(nvidia-smi -L 2>/dev/null | grep -c "^GPU" || echo 1)
    fi
    TP_FLAG=""
    [ "$GPU_COUNT" -gt 1 ] && TP_FLAG="--tensor-parallel-size $GPU_COUNT"
    EXEC_START_CMD="/opt/vllm/bin/python3 -m vllm.entrypoints.openai.api_server --model ${MODEL_DIR} --host 0.0.0.0 --port ${PORT} ${SERVE_ARGS}"
    if [ -n "$TP_FLAG" ]; then
      EXEC_START_CMD="${EXEC_START_CMD} ${TP_FLAG}"
    fi

    # Write the systemd unit that runs vLLM as a managed service.
    # [Unit]    : ordering + crashloop guard.
    #             - After/Wants nvidia-persistenced so the GPU driver is up before launch.
    #             - StartLimitBurst=5 / IntervalSec=300 stops infinite restart loops.
    # [Service] : how to run the process.
    #             - Type=simple: ExecStart IS the main pid (no readiness signal).
    #             - User=root + LimitMEMLOCK=infinity: vLLM/CUDA need to mlock GPU staging buffers.
    #             - Environment=...: pin Inductor/Triton caches per-model (fast first-boot, no
    #               cross-model corruption) and forward VLLM_ATTENTION_BACKEND from the bake.
    #             - ExecStartPre (run in order, all must succeed):
    #                 1. Recreate the /root/.cache/vllm/torch_compile_cache symlink so vLLM
    #                    finds the AOT cache at its hard-coded path.
    #                 2. vllm-warm-cache: dd-prefetch ~70GB of weights into page cache on cold
    #                    first boot (skips itself when disk is already hot).
    #                 3. Poll nvidia-smi up to 120s so we don't launch before the driver loads.
    #             - ExecStart: python -m vllm.entrypoints.openai.api_server with all per-model args.
    #             - Restart=on-failure / RestartSec=15: auto-recover from crashes, not from
    #               clean `systemctl stop`.
    #             - TimeoutStartSec=infinity: 70GB FP8 weights + torch.compile can take many
    #               minutes; the default 90s would kill a healthy boot.
    #             - StandardOutput/Error=journal: viewable via `journalctl -u vllm-<prefix>`
    #               or the `logs` CLI this script generates below.
    # [Install] : `WantedBy=multi-user.target` is what `systemctl enable` hooks into so the
    #             unit auto-starts at every boot.
    cat > /etc/systemd/system/vllm-${PREFIX}.service << SVCEOF
[Unit]
Description=vLLM ${DISPLAY_NAME} OpenAI-Compatible Server
After=network.target nvidia-persistenced.service
Wants=nvidia-persistenced.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vllm
Environment="PATH=/opt/vllm/bin:/usr/local/bin:/usr/bin:/bin"
Environment="TORCHINDUCTOR_CACHE_DIR=${INDUCTOR_CACHE_DIR}"
Environment="TRITON_CACHE_DIR=${COMPILE_CACHE_DIR}/triton"
Environment="VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS=1"
Environment="VLLM_ATTENTION_BACKEND=${ATTN_BACKEND}"
ExecStartPre=/bin/bash -c 'mkdir -p /root/.cache/vllm && ln -sfn ${COMPILE_CACHE_DIR}/torch_aot /root/.cache/vllm/torch_compile_cache 2>/dev/null || true'
ExecStartPre=/usr/local/bin/vllm-warm-cache ${MODEL_DIR} ${INDUCTOR_CACHE_DIR} ${COMPILE_CACHE_DIR}/triton
ExecStartPre=/bin/bash -c 'for i in \$(seq 1 60); do nvidia-smi > /dev/null 2>&1 && exit 0; sleep 2; done; echo "GPU not ready after 120s"; exit 1'
ExecStart=${EXEC_START_CMD}
LimitMEMLOCK=infinity
Restart=on-failure
RestartSec=15
TimeoutStartSec=infinity
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vllm-${PREFIX}

[Install]
WantedBy=multi-user.target
SVCEOF

    chmod 644 /etc/systemd/system/vllm-${PREFIX}.service
    systemctl daemon-reload
    systemctl enable vllm-${PREFIX}.service
    echo "  Service installed and enabled (auto-starts on boot)"
    echo "  GPUs detected: $GPU_COUNT"

    # Pre-warm CUDA kernel cache so customers get fast startup from VMI
    if [ "$SKIP_PREWARM" = true ]; then
        echo "  Skipping pre-warm (--skip-prewarm flag set)."
    else
        echo "Pre-warming vLLM CUDA kernel cache (this may take up to ${PREWARM_WAIT_MINUTES} minutes on first run)..."
        echo "Inductor cache will be saved to: ${INDUCTOR_CACHE_DIR}"
        PREWARM_T0=$(date +%s)
        systemctl start vllm-${PREFIX}.service
        # Large NCC models can spend substantial time in ExecStartPre page-cache warming
        # and then kernel compilation before health goes green.
        READY=false
        for i in $(seq 1 $((PREWARM_WAIT_MINUTES * 12))); do
            if curl -sf "http://localhost:${PORT}/health" > /dev/null 2>&1; then
                READY=true
                echo ""
                echo "  vLLM ready after $((i*5))s, running warmup inference..."
                # Smoke test: must return real content, not just HTTP 200.
                # Captured response is checked below before we let the bake
                # proceed to snapshot/publish.
                SMOKE_RESP=$(curl -sf "http://localhost:${PORT}/v1/chat/completions" \
                    -H "Content-Type: application/json" \
                    -d "{\"model\":\"${MODEL_DIR}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one short sentence.\"}],\"max_tokens\":32,\"temperature\":0}" 2>/dev/null || echo "")
                SMOKE_CONTENT=$(echo "$SMOKE_RESP" | python3 -c "import json,sys
try:
  d=json.load(sys.stdin)
  print((d.get('choices') or [{}])[0].get('message',{}).get('content','') or '')
except Exception:
  pass" 2>/dev/null || echo "")
                if [ -z "$SMOKE_CONTENT" ]; then
                    echo "  ERROR: Pre-publish smoke test failed — chat endpoint returned no content."
                    echo "  Raw response: ${SMOKE_RESP:0:500}"
                    echo "  === Last 100 journal lines ==="
                    journalctl -u vllm-${PREFIX}.service --no-pager -n 100 2>&1 | sed 's/^/    /' || true
                    systemctl stop vllm-${PREFIX}.service 2>/dev/null || true
                    exit 1
                fi
                echo "  Smoke test OK. Sample: ${SMOKE_CONTENT:0:200}"
                echo "  Warmup complete. Inductor cache saved to ${INDUCTOR_CACHE_DIR}."
                echo "  Cache size: $(du -sh ${INDUCTOR_CACHE_DIR} 2>/dev/null | cut -f1 || echo unknown)"
                break
            fi
            # Every 5 min: dump last few journal lines + service state so we can
            # see whether the unit is making progress, crashlooping, or stuck.
            if [ $((i % 60)) -eq 0 ]; then
                echo ""
                echo "  --- progress check at $((i*5))s ---"
                systemctl is-active vllm-${PREFIX}.service 2>/dev/null || true
                echo "  Restart count: $(systemctl show -p NRestarts --value vllm-${PREFIX}.service 2>/dev/null || echo unknown)"
                journalctl -u vllm-${PREFIX}.service --no-pager -n 15 2>/dev/null | sed 's/^/    /' || true
                echo "  --- end progress check ---"
            elif [ $((i % 6)) -eq 0 ]; then
                echo " $((i*5))s elapsed..."
            else
                echo -n "."
            fi
            sleep 5
        done
        PREWARM_ELAPSED=$(( $(date +%s) - PREWARM_T0 ))
        if [ "$READY" = false ]; then
            echo ""
            echo "  ERROR: Pre-warm timed out after ${PREWARM_WAIT_MINUTES} minutes (${PREWARM_ELAPSED}s)."
            echo "  === systemctl status vllm-${PREFIX}.service ==="
            systemctl status vllm-${PREFIX}.service --no-pager 2>&1 | sed 's/^/    /' || true
            echo "  === Last 200 journal lines for vllm-${PREFIX}.service ==="
            journalctl -u vllm-${PREFIX}.service --no-pager -n 200 2>&1 | sed 's/^/    /' || true
            echo "  === GPU state ==="
            nvidia-smi 2>&1 | sed 's/^/    /' || true
            systemctl stop vllm-${PREFIX}.service 2>/dev/null || true
            exit 1
        fi
        systemctl stop vllm-${PREFIX}.service
        # On cold VMI first-boot, customers need:
        #   - dd page-cache warm of weights (~70GB @ 47 MB/s blob redirect = ~20 min)
        #   - torch.compile + cudagraph capture (~80 s without compile cache)
        # With this bake-time prewarm writing the compile cache to disk + the
        # runtime dd-warm writing weights to page cache, first-boot drops from
        # ~25 min to ~1-2 min. Second boot (hydrated SSD, no dd needed) is ~45-90 s.
        echo "  Cache pre-warmed in ${PREWARM_ELAPSED}s. Customers: ~1-2 min first boot, ~45-90s second boot (vs ~25 min cold)."
    fi

    # create log checker utility
    cat > "${CLI_DIR}/logs" << 'LOGEOF'
#!/bin/bash
set -euo pipefail

ACTIVE_SVC=""
for svc in /etc/systemd/system/vllm-*.service; do
  [ -f "$svc" ] || continue
  svc_name=$(basename "$svc")
  if systemctl is-active "$svc_name" > /dev/null 2>&1; then
    ACTIVE_SVC="$svc_name"
    break
  fi
done

if [ -z "$ACTIVE_SVC" ]; then
  echo "No model service is currently active."
  echo "Check installed models with: cgpu model list"
  exit 1
fi

case "${1:-}" in
  -f|--follow) journalctl -u "$ACTIVE_SVC" -f ;;
  -e|--errors) journalctl -u "$ACTIVE_SVC" -p err --no-pager -n 50 ;;
  -a|--all)    journalctl -u "$ACTIVE_SVC" --no-pager ;;
  *)
    echo "=== $ACTIVE_SVC service status ==="
    systemctl status "$ACTIVE_SVC" --no-pager 2>/dev/null || true
    echo ""
    echo "=== Last 30 log lines ==="
    journalctl -u "$ACTIVE_SVC" --no-pager -n 30
    ;;
esac
LOGEOF
    chmod +x "${CLI_DIR}/logs"

    # model management utility
    cat > "${CLI_DIR}/model" << 'MODELEOF'
#!/bin/bash
# model management utility: list, serve, stop, delete, switch
set -euo pipefail

INSTALL_DIR="/usr/local/bin"
VENV_DIR="/opt/vllm"

model_id_to_name() {
  local model_id="$1"
  local repo="${model_id##*/}"

  if [[ "$repo" =~ [Dd]eep[Ss]eek- ]]; then
    echo "deepseek"
  elif [[ "$repo" =~ [Ll]lama- ]]; then
    echo "llama"
  elif [[ "$repo" =~ [Qq]wen ]]; then
    echo "qwen"
  elif [[ "$repo" =~ [Pp]hi- ]]; then
    echo "phi4"
  else
    echo "unknown"
  fi
}

model_id_to_service() {
  local model_id="${1,,}"
  local service_key="${model_id//\//--}"
  echo "vllm-${service_key}.service"
}

model_id_from_dir() {
  local d="$1"
  local version_file="$d/.cgpu-model-version"
  [ -f "$version_file" ] || { echo ""; return; }
  sed -n 's/^MODEL_ID=//p' "$version_file" | head -1 | tr '[:upper:]' '[:lower:]'
}

installed_model_dirs() {
  local version_file

  for version_file in /usr/local/lib/*/*/.cgpu-model-version; do
    [ -f "$version_file" ] || continue
    dirname "$version_file"
  done
}

find_model_dir() {
  local target="${1,,}"
  local target_dir="/usr/local/lib/${target}"
  local installed_model_id

  [ -f "$target_dir/.cgpu-model-version" ] || { echo ""; return; }
  installed_model_id=$(model_id_from_dir "$target_dir")
  if [ "$installed_model_id" = "$target" ]; then
    echo "$target_dir"
    return
  fi

  echo ""
}

stop_all_vllm() {
  for svc in /etc/systemd/system/vllm-*.service; do
    [ -f "$svc" ] || continue
    svc_name=$(basename "$svc")

    if systemctl is-active "$svc_name" > /dev/null 2>&1; then
      echo "Stopping $svc_name..."
      sudo systemctl stop "$svc_name" 2>/dev/null || true
      sudo systemctl disable "$svc_name" 2>/dev/null || true
    fi
  done
  sudo systemctl daemon-reload 2>/dev/null || true

  if pgrep -f "vllm.entrypoints" > /dev/null 2>&1; then
    echo "Stopping manual vLLM process..."
    sudo pkill -f "[v]llm.entrypoints" 2>/dev/null || true
    sleep 2
    sudo pkill -9 -f "[V]LLM::EngineCore" 2>/dev/null || true
    sudo pkill -9 -f "[v]llm.entrypoints" 2>/dev/null || true
  fi

  for pidfile in /var/run/*-serve.pid; do
    [ -f "$pidfile" ] || continue
    sudo kill "$(cat "$pidfile")" 2>/dev/null || true
    sudo rm -f "$pidfile"
  done
}

stop_other_vllm() {
  local keep_svc="$1"

  for svc in /etc/systemd/system/vllm-*.service; do
    [ -f "$svc" ] || continue
    svc_name=$(basename "$svc")

    if [ "$svc_name" = "$keep_svc" ]; then
      continue
    fi

    if systemctl is-active "$svc_name" > /dev/null 2>&1; then
      echo "Stopping $svc_name..."
      sudo systemctl stop "$svc_name" 2>/dev/null || true
      sudo systemctl disable "$svc_name" 2>/dev/null || true
    fi
  done

  sudo systemctl daemon-reload 2>/dev/null || true

  if pgrep -f "vllm.entrypoints" > /dev/null 2>&1; then
    echo "Stopping manual vLLM process..."
    sudo pkill -f "[v]llm.entrypoints" 2>/dev/null || true
    sleep 2
    sudo pkill -9 -f "[V]LLM::EngineCore" 2>/dev/null || true
    sudo pkill -9 -f "[v]llm.entrypoints" 2>/dev/null || true
  fi

  for pidfile in /var/run/*-serve.pid; do
    [ -f "$pidfile" ] || continue
    sudo kill "$(cat "$pidfile")" 2>/dev/null || true
    sudo rm -f "$pidfile"
  done
}

stop_model() {
  local target_dir="$1"
  local model_id svc_name
  model_id=$(model_id_from_dir "$target_dir")
  svc_name=$(model_id_to_service "$model_id")

  if [ -n "$svc_name" ] && [ -f "/etc/systemd/system/$svc_name" ]; then
    echo "Stopping service $svc_name..."
    sudo systemctl stop "$svc_name" 2>/dev/null || true
    sudo systemctl disable "$svc_name" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/$svc_name"
    sudo systemctl daemon-reload
  fi

  local pid
  pid=$(pgrep -af "vllm.entrypoints.*--model $target_dir" 2>/dev/null | awk '{print $1}' | head -1 || true)
  if [ -n "$pid" ]; then
    echo "Stopping vLLM process (PID $pid)..."
    sudo kill "$pid" 2>/dev/null || true
    for i in $(seq 1 30); do
      pgrep -af "vllm.entrypoints.*--model $target_dir" > /dev/null 2>&1 || break
      sudo pkill -9 -f "[V]LLM::EngineCore" 2>/dev/null || true
      sudo pkill -9 -f "[v]llm.entrypoints" 2>/dev/null || true
      sleep 2
    done
  fi

  for pidfile in /var/run/*-serve.pid; do
    [ -f "$pidfile" ] && sudo kill "$(cat "$pidfile")" 2>/dev/null || true
    sudo rm -f "$pidfile"
  done
}

wait_for_gpu_clear() {
  echo "Waiting for GPU memory to clear..."
  for i in $(seq 1 30); do
    used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' || echo "99999")
    if [ "$used" -lt 1000 ]; then
      echo "GPU memory cleared (${used}MiB used)."
      return
    fi
    sudo pkill -9 -f "[V]LLM::EngineCore" 2>/dev/null || true
    sudo pkill -9 -f "[v]llm.entrypoints" 2>/dev/null || true
    if [ $((i % 5)) -eq 0 ]; then
      echo "  Still clearing GPU memory (${used}MiB used)..."
    fi
    sleep 2
  done
  echo ""
}

wait_for_health() {
  echo "Waiting for model to load..."
  for i in $(seq 1 480); do
    if curl -sf "http://localhost:8000/health" > /dev/null 2>&1; then
      echo "Model is ready."
      return 0
    fi
    if [ $((i % 6)) -eq 0 ]; then
      echo "  $((i*5))s elapsed..."
    fi
    sleep 5
  done
  echo "Timeout. Check: cgpu logs -f"
  return 1
}

usage() {
  echo "Usage: cgpu model <command> [options]"
  echo ""
  echo "Commands:"
  echo "  list                                Show installed models"
  echo "  serve <model-id> [--api-key <key>]  Start serving a model"
  echo "  stop                                Stop the running model"
  echo "  delete <model-id>                   Stop and delete a model"
  echo "  switch <model-id>                   Switch model; download only if missing"
  echo ""
  echo "  --api-key <key>  require 'Authorization: Bearer <key>' on /v1/* for this session"
  echo "                   (a key value is required). Applies to this serve only --"
  echo "                   not written to disk; serving again without it drops the key."
  echo ""
  echo "Examples:"
  echo "  cgpu model list"
  echo "  cgpu model serve qwen/qwen3.8-27b"
  echo "  cgpu model stop"
  echo "  cgpu model delete qwen/qwen3.8-27b"
  echo "  cgpu model switch qwen/qwen3.8-27b"
}

create_model_service() {
  local model_id="$1"
  local model_dir="$2"
  local model_name
  local svc_name
  local cache_key
  local compile_cache_dir
  local inductor_cache_dir
  local serve_args=""
  local attn_backend=""

  model_name=$(model_id_to_name "$model_id")
  svc_name=$(model_id_to_service "$model_id")
  cache_key="${model_id//\//--}"
  compile_cache_dir="/var/cache/vllm-compile/${cache_key}"
  inductor_cache_dir="${compile_cache_dir}/inductor"

  case "$model_name" in
    phi4)
      serve_args="--max-model-len 16384 --trust-remote-code"
      ;;
    deepseek)
      serve_args="--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code"
      ;;
    llama)
      serve_args="--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code"
      ;;
    qwen)
      serve_args="--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code"
      ;;
    *)
      echo "Unable to determine runtime profile for $model_id"
      return 1
      ;;
  esac

  if [[ "${model_id##*/}" =~ ^qwen3\.(5|6|7|8|9)- ]]; then
    serve_args="${serve_args} --gdn-prefill-backend triton"
  fi

  if ! command -v nvcc >/dev/null 2>&1 && [ ! -x /usr/local/cuda/bin/nvcc ]; then
    attn_backend="FLASH_ATTN"
  fi

  serve_args="${serve_args} --compilation-config '{\"cache_dir\":\"${compile_cache_dir}\"}'"

  sudo mkdir -p "$compile_cache_dir" "$inductor_cache_dir" "${compile_cache_dir}/torch_aot" "${compile_cache_dir}/triton"

  sudo tee "/etc/systemd/system/${svc_name}" >/dev/null <<EOF
[Unit]
Description=vLLM ${model_id} OpenAI-Compatible Server
After=network.target nvidia-persistenced.service
Wants=nvidia-persistenced.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vllm
Environment="PATH=/opt/vllm/bin:/usr/local/bin:/usr/bin:/bin"
Environment="TORCHINDUCTOR_CACHE_DIR=${inductor_cache_dir}"
Environment="TRITON_CACHE_DIR=${compile_cache_dir}/triton"
Environment="VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS=1"
Environment="VLLM_ATTENTION_BACKEND=${attn_backend}"
ExecStartPre=/bin/bash -c 'mkdir -p /root/.cache/vllm && ln -sfn ${compile_cache_dir}/torch_aot /root/.cache/vllm/torch_compile_cache 2>/dev/null || true'
ExecStartPre=/usr/local/bin/vllm-warm-cache ${model_dir} ${inductor_cache_dir} ${compile_cache_dir}/triton
ExecStartPre=/bin/bash -c 'for i in \$(seq 1 60); do nvidia-smi > /dev/null 2>&1 && exit 0; sleep 2; done; echo "GPU not ready after 120s"; exit 1'
ExecStart=/opt/vllm/bin/python3 -m vllm.entrypoints.openai.api_server --model ${model_dir} --host 0.0.0.0 --port 8000 ${serve_args}
LimitMEMLOCK=infinity
Restart=on-failure
RestartSec=15
TimeoutStartSec=infinity
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vllm-${cache_key}

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable "$svc_name"
}

cmd="${1:-}"
case "$cmd" in

  list)
    echo "=== Installed Models ==="
    found=0
    installed_model_ids=()

    while IFS= read -r d; do
      [ -n "$d" ] || continue
      model_id=$(model_id_from_dir "$d")
      [ -n "$model_id" ] || continue

      size=$(du -sh "$d" 2>/dev/null | cut -f1)
      status=""
      svc=$(model_id_to_service "$model_id")

      if [ -n "$svc" ] && systemctl is-active "$svc" > /dev/null 2>&1; then
        status="  [serving via systemd]"
      elif pgrep -af "vllm.entrypoints.*--model $d" > /dev/null 2>&1; then
        status="  [serving manually]"
      fi

      echo "  $model_id  ($size)  $d$status"
      installed_model_ids+=("$model_id")
      found=$((found + 1))
    done < <(installed_model_dirs)

    if [ "$found" -eq 0 ]; then
      echo "  No models installed"
    fi

    validated_models=(
      "microsoft/phi-4"
      "qwen/qwen3.8-27b"
      "redhatai/qwen2.5-72b-instruct-fp8-dynamic"
      "redhatai/llama-3.3-70b-instruct-fp8-dynamic"
      "redhatai/deepseek-r1-distill-llama-70b-fp8-dynamic"
    )

    not_installed=()
    for candidate in "${validated_models[@]}"; do
      installed=false
      for installed_model_id in "${installed_model_ids[@]}"; do
        if [ "$installed_model_id" = "$candidate" ]; then
          installed=true
          break
        fi
      done
      [ "$installed" = true ] || not_installed+=("$candidate")
    done

    if [ ${#not_installed[@]} -gt 0 ]; then
      echo ""
      echo "=== Not Installed Validated Models ==="
      for model_id in "${not_installed[@]}"; do
        echo "  $model_id"
      done
      echo ""
      echo "Install with:"
      echo "  cgpu model switch <model-id>"
      echo ""
      echo "Examples:"
      echo "    cgpu model switch microsoft/phi-4"
    fi
    ;;

  serve)
    shift  # drop 'serve'
    target=""
    # API key is OFF by default and applies only to this serve session -- it is
    # never written to persistent disk. When provided, it is injected via a /run
    # (tmpfs, RAM-backed) systemd drop-in that is cleared on reboot and replaced on
    # each serve. Stop+serve or reboot without --api-key drops the key.
    #   --api-key <key>   require 'Authorization: Bearer <key>' for this session
    API_KEY=""
    API_KEY_SET=false
    while [ $# -gt 0 ]; do
      case "$1" in
        --api-key)
          API_KEY_SET=true
          if [ -n "${2:-}" ] && [ "${2#--}" = "${2:-}" ]; then API_KEY="$2"; shift 2
          else echo "No API key given."; exit 1; fi ;;
        *) target="$1"; shift ;;
      esac
    done

    if [ -z "$target" ]; then
      echo "Usage: cgpu model serve <model-id> [--api-key <key>]"
      exit 1
    fi

    target="${target,,}"
    if [[ ! "$target" =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ ]]; then
      echo "Invalid Hugging Face model ID: $target"
      echo "Expected format: <organization-or-user>/<repository>"
      exit 1
    fi

    target_svc=$(model_id_to_service "$target")
    if [ -z "$target_svc" ]; then
      echo "Unable to determine service for model ID: $target"
      exit 1
    fi

    target_dir=$(find_model_dir "$target")

    # Install only when the model weights are not already installed.
    if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
      echo "Model $target is not installed."
      echo "Installing $target..."

      sudo bash /usr/local/lib/utilities-launch-vllm.sh \
        --model-id "$target" --install-to-service --skip-prewarm

      target_dir=$(find_model_dir "$target")
      if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
        echo "ERROR: Model installation did not create the expected model directory."
        exit 1
      fi
    else
      echo "Model '$target' already installed in $target_dir"
    fi

    # An installed model should already have its model-specific service.
    # Do not rerun the full installer just to recreate a missing service.
    if [ ! -f "/etc/systemd/system/$target_svc" ]; then
      echo "Model is installed but its service is missing."
      echo "Recreating service for $target..."
      create_model_service "$target" "$target_dir"
    fi

    # /run is tmpfs (RAM) -- the key is never written to persistent disk and is
    # gone on reboot.
    dropin_dir="/run/systemd/system/${target_svc}.d"
    dropin="$dropin_dir/apikey.conf"

    # Skip work only when the service is already up AND the requested auth state
    # already matches the running one. If a key is present but not requested (or
    # vice versa), fall through so we can (re)apply it and restart.
    if [ "$API_KEY_SET" = false ] && [ ! -e "$dropin" ] && systemctl is-active "$target_svc" > /dev/null 2>&1; then
      echo "$target is already serving."
      exit 0
    fi
    if [ "$API_KEY_SET" = false ] && [ -e "$dropin" ]; then
      echo "Removing the API key and restarting $target unauthenticated..."
    fi

    # Stop other model services, but keep their service files so installed models
    # can be started again without rerunning the installer.
    for svc in /etc/systemd/system/vllm-*.service; do
      [ -f "$svc" ] || continue
      svc_name=$(basename "$svc")
      if [ "$svc_name" != "$target_svc" ]; then
        if systemctl is-active "$svc_name" > /dev/null 2>&1; then
          echo "Stopping $svc_name..."
          sudo systemctl stop "$svc_name" 2>/dev/null || true
        fi
        sudo systemctl disable "$svc_name" 2>/dev/null || true
      fi
    done

    # Stop the target too when we need to restart it to change API-key state.
    sudo systemctl stop "$target_svc" 2>/dev/null || true

    if pgrep -f "vllm.entrypoints" > /dev/null 2>&1; then
      echo "Stopping manual vLLM process..."
      sudo pkill -f "[v]llm.entrypoints" 2>/dev/null || true
      sleep 2
      sudo pkill -9 -f "[V]LLM::EngineCore" 2>/dev/null || true
      sudo pkill -9 -f "[v]llm.entrypoints" 2>/dev/null || true
    fi

    for pidfile in /var/run/*-serve.pid; do
      [ -f "$pidfile" ] && sudo kill "$(cat "$pidfile")" 2>/dev/null || true
      sudo rm -f "$pidfile"
    done

    wait_for_gpu_clear

    # Apply the API key for this session only, via a /run (tmpfs) drop-in. This is
    # never written to persistent disk and is cleared on reboot. A serve without
    # --api-key removes any stale key so the session starts unauthenticated.
    if [ "$API_KEY_SET" = true ] && [ -n "$API_KEY" ]; then
      sudo mkdir -p "$dropin_dir"
      printf '[Service]\nEnvironment=VLLM_API_KEY=%s\n' "$API_KEY" | sudo tee "$dropin" >/dev/null
      sudo chmod 600 "$dropin"
      echo "API key enabled for this session only (not persisted; cleared on stop/serve or reboot)."
    else
      [ -e "$dropin" ] && sudo rm -f "$dropin"
    fi

    sudo systemctl daemon-reload
    sudo systemctl enable "$target_svc" >/dev/null 2>&1 || true

    echo "Starting $target..."
    if ! sudo systemctl start "$target_svc"; then
      echo ""
      echo "ERROR: Failed to start $target."
      echo ""
      echo "=== systemctl status ==="
      sudo systemctl status "$target_svc" --no-pager -l || true
      echo ""
      echo "=== Last 200 service log lines ==="
      sudo journalctl -u "$target_svc" --no-pager -n 200 -o cat || true
      exit 1
    fi

    if wait_for_health; then
      echo "$target is serving on http://localhost:8000/v1"
    fi
    ;;

  stop)
    if [ -n "${2:-}" ]; then
      echo "Usage: cgpu model stop"
      echo "Stops the currently serving model."
      exit 1
    fi

    if ! pgrep -f "vllm.entrypoints" > /dev/null 2>&1; then
      running_svc=""
      for svc in /etc/systemd/system/vllm-*.service; do
        [ -f "$svc" ] || continue
        svc_name=$(basename "$svc")
        if systemctl is-active "$svc_name" > /dev/null 2>&1; then
          running_svc="$svc_name"
          break
        fi
      done
      if [ -z "$running_svc" ]; then
        echo "vLLM is not running."
        exit 0
      fi
    fi
    stop_all_vllm
    echo "Stopped."
    ;;

  delete)
    target="${2:-}"
    if [ -z "$target" ]; then
      echo "Usage: cgpu model delete <model-id>"
      exit 1
    fi

    target="${target,,}"
    if [[ ! "$target" =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ ]]; then
      echo "Invalid Hugging Face model ID: $target"
      echo "Expected format: <organization-or-user>/<repository>"
      exit 1
    fi

    target_dir=$(find_model_dir "$target")
    if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
      echo "Model $target is not installed."
      exit 1
    fi

    deleted_model_id=$(model_id_from_dir "$target_dir")
    stop_model "$target_dir"

    echo "Deleting model weights at $target_dir..."
    sudo rm -rf "$target_dir"
    echo "Deleted $deleted_model_id."
    ;;

  switch)
    new_model_id="${2:-}"
    if [ -z "$new_model_id" ]; then
      echo "Usage: cgpu model switch <model-id>"; exit 1
    fi

    new_model_id="${new_model_id,,}"
    if [[ ! "$new_model_id" =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ ]]; then
      echo "Invalid Hugging Face model ID: $new_model_id"
      echo "Expected format: <organization-or-user>/<repository>"
      exit 1
    fi

    new_model=$(model_id_to_name "$new_model_id")
    if [ "$new_model" = "unknown" ]; then
      echo "Unable to determine a supported runtime profile from model ID: $new_model_id"
      exit 1
    fi

    new_svc=$(model_id_to_service "$new_model_id")
    if [ -z "$new_svc" ]; then
      echo "Unable to determine service for model ID: $new_model_id"
      exit 1
    fi

    new_dropin="/run/systemd/system/${new_svc}.d/apikey.conf"

    if systemctl is-active "$new_svc" > /dev/null 2>&1; then
      if [ ! -e "$new_dropin" ]; then
        echo "$new_model_id is already serving."
        exec "$INSTALL_DIR/cgpu" chat
      fi

      echo "Removing the API key and restarting $new_model_id unauthenticated..."
      sudo systemctl stop "$new_svc" 2>/dev/null || true
      sudo rm -f "$new_dropin"
      sudo systemctl daemon-reload
    fi

    stop_other_vllm "$new_svc"

    # Clear shared vLLM graph cache
    sudo rm -rf /var/cache/vllm-compile/rank_0_0 2>/dev/null || true
    sudo rm -rf /var/cache/vllm-compile/torch_aot 2>/dev/null || true
    sudo mkdir -p /var/cache/vllm-compile/torch_aot
    echo "Cleared vLLM graph cache."

    wait_for_gpu_clear

    new_model_dir=$(find_model_dir "$new_model_id")

    if [ -n "$new_model_dir" ] && [ -d "$new_model_dir" ]; then
      echo "Model $new_model_id already installed in $new_model_dir"

      if [ ! -f "/etc/systemd/system/$new_svc" ]; then
        echo "Model service is missing."
        echo "Recreating service for $new_model_id..."
        create_model_service "$new_model_id" "$new_model_dir"
      fi
    else
      echo "Installing ${new_model_id} (this will take 10-20 minutes depending on model size)..."
      INSTALL_T0=$(date +%s)
      sudo bash /usr/local/lib/utilities-launch-vllm.sh --model-id "$new_model_id" --install-to-service --skip-prewarm

      INSTALL_ELAPSED=$(( $(date +%s) - INSTALL_T0 ))
      echo "Install (download + setup) complete in ${INSTALL_ELAPSED}s."
    fi

    # Start the correct service by name
    echo "Starting ${new_model_id} service..."
    LOAD_T0=$(date +%s)
    sudo systemctl reset-failed "$new_svc" 2>/dev/null || true
    sudo systemctl enable "$new_svc" 2>/dev/null || true
    sudo systemctl start "$new_svc"

    if wait_for_health; then
      LOAD_ELAPSED=$(( $(date +%s) - LOAD_T0 ))
      echo "Model loaded and ready in ${LOAD_ELAPSED}s. Launching chat..."
      exec "$INSTALL_DIR/cgpu" chat
    fi
    ;;

  *)
    usage; exit 0 ;;
esac
MODELEOF
    chmod +x "${CLI_DIR}/model"
fi

# motd
rm -f /etc/motd

cat > /etc/update-motd.d/99-cgpu << 'MOTDEOF'
#!/bin/bash

ACTIVE_SVC=""
MODEL_ID=""
MODEL_DIR=""
CACHE_DIR=""
INDUCTOR_DIR=""

for svc in /etc/systemd/system/vllm-*.service; do
    [ -f "$svc" ] || continue
    svc_name=$(basename "$svc")

    if systemctl is-active "$svc_name" >/dev/null 2>&1; then
        ACTIVE_SVC="$svc_name"
        break
    fi
done

if [ -n "$ACTIVE_SVC" ]; then
    for version_file in /usr/local/lib/*/*/.cgpu-model-version; do
        [ -f "$version_file" ] || continue

        candidate_id=$(sed -n 's/^MODEL_ID=//p' "$version_file" | head -1 | tr '[:upper:]' '[:lower:]')
        [ -n "$candidate_id" ] || continue

        candidate_svc="vllm-${candidate_id//\//--}.service"

        if [ "$candidate_svc" = "$ACTIVE_SVC" ]; then
            MODEL_ID="$candidate_id"
            MODEL_DIR=$(dirname "$version_file")
            break
        fi
    done
fi

if [ -n "$MODEL_ID" ]; then
    CACHE_KEY="${MODEL_ID//\//--}"
    CACHE_DIR="/var/cache/vllm-compile/${CACHE_KEY}"
    INDUCTOR_DIR="${CACHE_DIR}/inductor"
fi

echo ""

if [ -n "$MODEL_ID" ]; then
    echo " 🚀 ${MODEL_ID} CGPU VM -- Ready"
else
    echo " 🚀 CGPU VM -- Ready"
fi

echo " -----------------------------------------"
echo " 💬 cgpu chat [--system \"...\"]"
echo " ▶️ cgpu serve <model-id> [--daemon|--stop|--status]  (needs sudo)"
echo " ⚡ cgpu bench"
echo " 📊 cgpu throughput [-n 100] [--request-rate 50] [--api-key <key>]"
echo " 📜 cgpu logs [-f|--follow] [-e|--errors]"
echo " 🔧 cgpu model list|serve|stop|delete|switch <model-id>"
echo " 🔑 Optional auth: cgpu model serve <model-id> --api-key <key> (this session only)"
echo ""

if [ -n "$ACTIVE_SVC" ]; then
    echo " ⚙️ Service:  sudo systemctl status ${ACTIVE_SVC}"
    echo " 🌐 API:      http://localhost:8000/v1"
    echo " 🧠 Model:    ${MODEL_DIR}"
    echo " 🐍 venv:     /opt/vllm"
    echo " 💾 Cache:    ${CACHE_DIR}"
    echo " ⚡ Inductor: ${INDUCTOR_DIR}"
else
    echo " ⚙️ Service:  no model currently serving"
    echo " 🌐 API:      not running"
    echo " 🧠 Model:    none"
    echo " 🐍 venv:     /opt/vllm"
fi

echo ""
MOTDEOF
chmod +x /etc/update-motd.d/99-cgpu

echo "============================================"
echo "  ${DISPLAY_NAME} installation complete!"
if [ "$INSTALL_SERVICE" = true ]; then
    echo "  Systemd service: enabled (auto-start on boot)"
    echo "  Compile cache:   ${COMPILE_CACHE_DIR}"
    echo "  Inductor cache:  ${INDUCTOR_CACHE_DIR}"
    echo "  Manual: sudo systemctl start vllm-${PREFIX}"
fi
echo "============================================"




