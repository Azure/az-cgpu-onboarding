#!/bin/bash
# ----------------------------------------------------------------------------
# Multi-model vLLM installer + launcher utility
#
# Usage:
#   sudo bash utilities-launch-vllm.sh --model phi4                        # Install venv + download model + create CLI tools
#   sudo bash utilities-launch-vllm.sh --model phi4 --install-to-service   # Same + create systemd service (auto-start on boot)
#
# Supported models: phi4, deepseek, llama, qwen
# ----------------------------------------------------------------------------
 
set -euo pipefail
 
VENV_DIR="/opt/vllm"
INSTALL_DIR="/usr/local/bin"
# Backing scripts for the `cgpu` subcommands live here; users invoke them via the
# single `cgpu` dispatcher installed into INSTALL_DIR (e.g. `cgpu chat`, `cgpu serve`).
CLI_DIR="/usr/local/lib/cgpu-cli"
INSTALL_SERVICE=false
SKIP_PREWARM=false
MODEL_NAME=""
CACHE_ROOT="/var/cache/vllm-compile"
COMPILE_CACHE_DIR=""
INDUCTOR_CACHE_DIR=""
# Pin vllm to the last known-good version (0.20.0 broke FP8 Distill-Llama init
# on driver 590 / CUDA 13.1; 0.19.1 was the version baked into the green
# qwen2.5-72b VMI). Override via VLLM_VERSION env var if needed.
VLLM_VERSION="${VLLM_VERSION:-0.19.1}"
ATTN_BACKEND=""
 
# Parse CLI arguments. Walks $@ one token at a time:
#   --model <name>          consume 2 tokens; set MODEL_NAME (phi4|deepseek|llama|qwen)
#   --install-to-service    boolean flag; create + enable the systemd unit
#   --skip-prewarm          boolean flag; skip the bake-time CUDA cache pre-warm
#                           (used by `cgpu model switch` at runtime; pipeline omits it)
# Anything else aborts with a non-zero exit so typos don't silently no-op.
while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL_NAME="$2"; shift 2 ;;
    --install-to-service) INSTALL_SERVICE=true; shift ;;
    --skip-prewarm) SKIP_PREWARM=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done
 
if [ -z "$MODEL_NAME" ]; then
    echo "Usage: $0 --model <phi4|deepseek|llama|qwen> [--install-to-service]"
    exit 1
fi
 
# Model-specific configuration
case "$MODEL_NAME" in
  phi4)
    MODEL_ID="microsoft/phi-4"
    MODEL_DIR="/usr/local/lib/phi-4"
    PREFIX="phi4"
    DISPLAY_NAME="Phi-4"
    MODEL_SIZE="~30GB"
    PORT=8000
    SERVE_ARGS="--max-model-len 16384 --trust-remote-code"
    SYS_PROMPT="You are Phi-4, a helpful AI assistant. Answer concisely and accurately."
    ;;
  deepseek)
    MODEL_ID="RedHatAI/DeepSeek-R1-Distill-Llama-70B-FP8-dynamic"
    MODEL_DIR="/usr/local/lib/deepseek-r1-70b"
    PREFIX="dsr1"
    DISPLAY_NAME="DeepSeek R1 Distill Llama 70B"
    MODEL_SIZE="~70GB"
    PORT=8000
    SERVE_ARGS="--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code"
    SYS_PROMPT=""
    ;;
  llama)
    MODEL_ID="RedHatAI/Llama-3.3-70B-Instruct-FP8-dynamic"
    MODEL_DIR="/usr/local/lib/llama-3.3-70b"
    PREFIX="llama"
    DISPLAY_NAME="Llama 3.3 70B"
    MODEL_SIZE="~70GB"
    PORT=8000
    SERVE_ARGS="--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code"
    SYS_PROMPT="You are a helpful, respectful and honest assistant."
    ;;
  qwen)
    MODEL_ID="RedHatAI/Qwen2.5-72B-Instruct-FP8-dynamic"
    MODEL_DIR="/usr/local/lib/qwen2.5-72b"
    PREFIX="qwen"
    DISPLAY_NAME="Qwen 2.5 72B"
    MODEL_SIZE="~70GB"
    PORT=8000
    SERVE_ARGS="--max-model-len 4096 --gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256 --trust-remote-code"
    SYS_PROMPT="You are Qwen, a helpful AI assistant created by Alibaba Cloud."
    ;;
  *)
    echo "Unknown model: $MODEL_NAME. Supported: phi4, deepseek, llama, qwen"
    exit 1
    ;;
esac

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
COMPILE_CACHE_DIR="${CACHE_ROOT}/${PREFIX}"
INDUCTOR_CACHE_DIR="${CACHE_ROOT}/${PREFIX}/inductor"
 
# Append compilation-config now that COMPILE_CACHE_DIR is known
SERVE_ARGS="${SERVE_ARGS} --compilation-config {\\\"cache_dir\\\":\\\"${COMPILE_CACHE_DIR}\\\"}"
 
echo "============================================"
echo "  ${DISPLAY_NAME} CGPU Installer"
echo "============================================"
 
# Clean up any existing vllm services that don't match current model
# This prevents stale service files from carrying over into the VMI
for svc in /etc/systemd/system/vllm-*.service; do
    [ -f "$svc" ] || continue
    svc_name=$(basename "$svc")
    if [ "$svc_name" != "vllm-${PREFIX}.service" ]; then
        echo "Removing stale service: $svc_name"
        systemctl stop "$svc_name" 2>/dev/null || true
        systemctl disable "$svc_name" 2>/dev/null || true
        rm -f "$svc"
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
# Pre-reads model weights into page cache before vLLM starts.
# Cold disk (VMI first boot): ~47 MB/s. Warm RAM: ~19 GB/s.
export TORCHINDUCTOR_CACHE_DIR="INDUCTOR_DIR_PLACEHOLDER"
export TRITON_CACHE_DIR="TRITON_DIR_PLACEHOLDER"
MODEL_DIR="MODEL_DIR_PLACEHOLDER"

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
find "$MODEL_DIR" -name "*.safetensors" | xargs -P8 -I{} dd if={} of=/dev/null bs=4M 2>/dev/null
WARM_ELAPSED=$(( $(date +%s) - WARM_T0 ))
echo "Prefetch complete in ${WARM_ELAPSED}s."
WARMEOF

sed -i "s|MODEL_DIR_PLACEHOLDER|${MODEL_DIR}|g" /usr/local/bin/vllm-warm-cache
sed -i "s|INDUCTOR_DIR_PLACEHOLDER|${INDUCTOR_CACHE_DIR}|g" /usr/local/bin/vllm-warm-cache
sed -i "s|TRITON_DIR_PLACEHOLDER|${COMPILE_CACHE_DIR}/triton|g" /usr/local/bin/vllm-warm-cache
chmod +x /usr/local/bin/vllm-warm-cache

# venv + vllm
echo "[1/6] Setting up Python venv + vLLM..."
# Ubuntu's system Python does not ship the venv/ensurepip module by default
# (e.g. Ubuntu 24.04 / Python 3.12), so `python3 -m venv` fails with
# "ensurepip is not available". Install the matching python3-venv package first.
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
sudo apt-get -o DPkg::Lock::Timeout=300 update
sudo apt-get -o DPkg::Lock::Timeout=300 install -y "python3-venv" "python${PY_VER}-venv" || \
    sudo apt-get -o DPkg::Lock::Timeout=300 install -y python3-venv
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip "setuptools>=77.0.3,<81.0.0" wheel -q
# Pin vllm to last known-good version (0.20.0 broke FP8 Distill-Llama init on
# driver 590 / CUDA 13.1; 0.19.1 was the version baked into the green
# qwen2.5-72b VMI). Override via VLLM_VERSION env var if needed.
pip install "vllm==${VLLM_VERSION}" huggingface-hub -q
 
# model weights
echo "[2/6] Downloading ${DISPLAY_NAME} model weights..."
mkdir -p "$MODEL_DIR"

DOWNLOAD_T0=$(date +%s)
python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(repo_id='${MODEL_ID}', local_dir='${MODEL_DIR}', ignore_patterns=['*.gguf'])
"
DOWNLOAD_ELAPSED=$(( $(date +%s) - DOWNLOAD_T0 ))
MODEL_SIZE_ON_DISK=$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1 || echo unknown)
echo "  Download complete in ${DOWNLOAD_ELAPSED}s (${MODEL_SIZE_ON_DISK} on disk)."
deactivate
 
# serve
echo "[3/6] Creating cgpu serve command..."
mkdir -p "${CLI_DIR}"
cat > "${CLI_DIR}/serve" << EOF
#!/bin/bash
set -euo pipefail
if [ "\$(id -u)" -ne 0 ]; then
  echo "cgpu serve must be run as root (it writes to /var/log and /var/run)."
  echo "Re-run with sudo, e.g.: sudo cgpu serve \${1:-}"
  echo "For normal use prefer: cgpu model serve"
  exit 1
fi
source /opt/vllm/bin/activate
MODEL="${MODEL_DIR}"
PORT=${PORT}
LOG="/var/log/${PREFIX}"
PID="/var/run/${PREFIX}-serve.pid"
mkdir -p "\$LOG"
 
stop_server() {
  [ -f "\$PID" ] && kill "\$(cat "\$PID")" 2>/dev/null && rm -f "\$PID" && echo "Stopped." || echo "Not running."
}
 
# Parse args. Supports the mode flags plus an optional --api-key.
#   --api-key <key>  enable auth with the given key for this run (errors if no value)
# The key applies only to this process/session -- it is not written to disk.
DAEMON=false
API_KEY=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --stop)   stop_server; exit 0 ;;
    --status) [ -f "\$PID" ] && kill -0 "\$(cat "\$PID")" 2>/dev/null && echo "Running (PID \$(cat "\$PID")) -> http://localhost:\$PORT/v1" || echo "Not running."; exit 0 ;;
    --daemon) DAEMON=true; shift ;;
    --api-key)
      if [ -n "\${2:-}" ] && [ "\${2#--}" = "\${2:-}" ]; then API_KEY="\$2"; shift 2
      else echo "No API key given."; exit 1; fi ;;
    *) echo "Unknown option: \$1"; exit 1 ;;
  esac
done
 
[ -n "\$API_KEY" ] && export VLLM_API_KEY="\$API_KEY"
 
if [ "\$DAEMON" = true ]; then
  if [ -n "${ATTN_BACKEND}" ]; then
    export VLLM_ATTENTION_BACKEND=${ATTN_BACKEND}
  fi
  export TORCHINDUCTOR_CACHE_DIR=${INDUCTOR_CACHE_DIR}
  export TRITON_CACHE_DIR=${COMPILE_CACHE_DIR}/triton
  mkdir -p /root/.cache/vllm && ln -sfn ${COMPILE_CACHE_DIR}/torch_aot /root/.cache/vllm/torch_compile_cache 2>/dev/null || true
  nohup python3 -m vllm.entrypoints.openai.api_server \\
    --model "\$MODEL" --host 0.0.0.0 --port \$PORT \\
    ${SERVE_ARGS} > "\$LOG/serve.log" 2>&1 &
  echo \$! > "\$PID"
  echo -n "Waiting for model to load "
  for i in \$(seq 1 600); do
    curl -s "http://localhost:\$PORT/health" > /dev/null 2>&1 && echo " Ready" && exit 0
    echo -n "."; sleep 1
  done
  echo " Timeout -- check \$LOG/serve.log"; exit 1
else
  if [ -n "${ATTN_BACKEND}" ]; then
    export VLLM_ATTENTION_BACKEND=${ATTN_BACKEND}
  fi
  python3 -m vllm.entrypoints.openai.api_server \\
    --model "\$MODEL" --host 0.0.0.0 --port \$PORT \\
    ${SERVE_ARGS}
fi
EOF
chmod +x "${CLI_DIR}/serve"
 
# chat
echo "[4/6] Creating cgpu chat command..."
if [ -n "$SYS_PROMPT" ]; then
cat > "${CLI_DIR}/chat" << EOF
#!/bin/bash
set -euo pipefail
PORT=${PORT}
URL="http://localhost:\$PORT/v1/chat/completions"
MODEL="${MODEL_DIR}"
SYS="${SYS_PROMPT}"
# Optional API key: --api-key <key> (a value is required; errors otherwise).
# Sent as 'Authorization: Bearer <key>'. Omit it if the server has no key set.
API_KEY=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --system)  [ -n "\${2:-}" ] && SYS="\$2"; shift 2 ;;
    --api-key)
      if [ -n "\${2:-}" ] && [ "\${2#--}" = "\${2:-}" ]; then API_KEY="\$2"; shift 2
      else echo "No API key given."; exit 1; fi ;;
    *) shift ;;
  esac
done
AUTH=()
[ -n "\$API_KEY" ] && AUTH=(-H "Authorization: Bearer \$API_KEY")
if ! curl -s "http://localhost:\$PORT/health" > /dev/null 2>&1; then
  echo "Starting ${DISPLAY_NAME}..."
  sudo systemctl start vllm-${PREFIX}.service 2>/dev/null || { echo "Service not found. Run: sudo cgpu serve --daemon"; exit 1; }
  echo -n "Waiting for model to load "
  for _i in \$(seq 1 600); do
    curl -s "http://localhost:\$PORT/health" > /dev/null 2>&1 && break
    echo -n "."; sleep 1
  done
  echo ""
  curl -s "http://localhost:\$PORT/health" > /dev/null 2>&1 || { echo "Timed out. Check: cgpu logs -f"; exit 1; }
fi
# Preflight auth check: /v1/models requires the API key if one is set.
CODE=\$(curl -s -o /dev/null -w "%{http_code}" "\${AUTH[@]}" "http://localhost:\$PORT/v1/models" 2>/dev/null || echo 000)
if [ "\$CODE" = "401" ]; then
  if [ -n "\$API_KEY" ]; then
    echo "The API key was rejected (401). Check the key and retry: cgpu chat --api-key <key>"
  else
    echo "This server requires an API key. Re-run: cgpu chat --api-key <key>"
    echo "(or restart it without a key: cgpu model serve)"
  fi
  exit 1
fi
echo "${DISPLAY_NAME} Chat -- /quit to exit, /clear to reset"
MSGS=\$(jq -n --arg s "\$SYS" '[{"role":"system","content":\$s}]')
while echo -ne "\033[1;36mYou > \033[0m" && read -r INPUT; do
  case "\$INPUT" in
    /quit|/q) exit 0 ;; /clear) MSGS=\$(jq -n --arg s "\$SYS" '[{"role":"system","content":\$s}]'); continue ;; "") continue ;;
  esac
  MSGS=\$(echo "\$MSGS" | jq --arg m "\$INPUT" '. + [{"role":"user","content":\$m}]')
  RESP=\$(curl -s "\$URL" -H "Content-Type: application/json" "\${AUTH[@]}" \\
    -d "\$(jq -n --arg model "\$MODEL" --argjson msgs "\$MSGS" '{model:\$model,messages:\$msgs,max_tokens:2048,temperature:0.7,chat_template_kwargs:{enable_thinking:false}}')")
  RAW_ANS=\$(echo "\$RESP" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
  [ -z "\$RAW_ANS" ] && { echo "Error: \$(echo "\$RESP" | jq -r '(.error.message? // .error? // .message? // "unknown")' 2>/dev/null || echo "\$RESP")"; continue; }
  ANS=\$(python3 - "\$RAW_ANS" << 'PYEOF'
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
  echo -e "\033[1;32m${DISPLAY_NAME} > \033[0m\$ANS\n"
  MSGS=\$(echo "\$MSGS" | jq --arg m "\$ANS" '. + [{"role":"assistant","content":\$m}]')
done
EOF
else
# No system prompt (e.g. DeepSeek)
cat > "${CLI_DIR}/chat" << EOF
#!/bin/bash
set -euo pipefail
PORT=${PORT}
URL="http://localhost:\$PORT/v1/chat/completions"
MODEL="${MODEL_DIR}"
# Optional API key: --api-key <key>. Sent as 'Authorization: Bearer <key>'.
API_KEY=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --api-key)
      if [ -n "\${2:-}" ] && [ "\${2#--}" = "\${2:-}" ]; then API_KEY="\$2"; shift 2
      else echo "No API key given."; exit 1; fi ;;
    *) shift ;;
  esac
done
AUTH=()
[ -n "\$API_KEY" ] && AUTH=(-H "Authorization: Bearer \$API_KEY")
if ! curl -s "http://localhost:\$PORT/health" > /dev/null 2>&1; then
  echo "Starting ${DISPLAY_NAME}..."
  sudo systemctl start vllm-${PREFIX}.service 2>/dev/null || { echo "Service not found. Run: sudo cgpu serve --daemon"; exit 1; }
  echo -n "Waiting for model to load "
  for _i in \$(seq 1 600); do
    curl -s "http://localhost:\$PORT/health" > /dev/null 2>&1 && break
    echo -n "."; sleep 1
  done
  echo ""
  curl -s "http://localhost:\$PORT/health" > /dev/null 2>&1 || { echo "Timed out. Check: cgpu logs -f"; exit 1; }
fi
# Preflight auth check: /v1/models requires the API key if one is set.
CODE=\$(curl -s -o /dev/null -w "%{http_code}" "\${AUTH[@]}" "http://localhost:\$PORT/v1/models" 2>/dev/null || echo 000)
if [ "\$CODE" = "401" ]; then
  if [ -n "\$API_KEY" ]; then
    echo "The API key was rejected (401). Check the key and retry: cgpu chat --api-key <key>"
  else
    echo "This server requires an API key. Re-run: cgpu chat --api-key <key>"
    echo "(or restart it without a key: cgpu model serve)"
  fi
  exit 1
fi
echo "${DISPLAY_NAME} Chat -- /quit to exit, /clear to reset"
MSGS="[]"
while echo -ne "\033[1;36mYou > \033[0m" && read -r INPUT; do
  case "\$INPUT" in
    /quit|/q) exit 0 ;; /clear) MSGS="[]"; continue ;; "") continue ;;
  esac
  MSGS=\$(echo "\$MSGS" | jq --arg m "\$INPUT" '. + [{"role":"user","content":\$m}]')
  RESP=\$(curl -s "\$URL" -H "Content-Type: application/json" "\${AUTH[@]}" \\
    -d "\$(jq -n --arg model "\$MODEL" --argjson msgs "\$MSGS" '{model:\$model,messages:\$msgs,max_tokens:2048,temperature:0.7}')")
  RAW_ANS=\$(echo "\$RESP" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
  [ -z "\$RAW_ANS" ] && { echo "Error: \$(echo "\$RESP" | jq -r '(.error.message? // .error? // .message? // "unknown")' 2>/dev/null || echo "\$RESP")"; continue; }
  ANS=\$(python3 - "\$RAW_ANS" << 'PYEOF'
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
  echo -e "\033[1;32m${DISPLAY_NAME} > \033[0m\$ANS\n"
  MSGS=\$(echo "\$MSGS" | jq --arg m "\$ANS" '. + [{"role":"assistant","content":\$m}]')
done
EOF
fi
chmod +x "${CLI_DIR}/chat"
 
# bench + throughput
echo "[5/6] Creating cgpu bench + cgpu throughput commands..."
cat > "${CLI_DIR}/bench" << EOF
#!/bin/bash
set -euo pipefail
PORT=${PORT}; MODEL="${MODEL_DIR}"
# Optional API key: --api-key <key>. Sent as 'Authorization: Bearer <key>'.
API_KEY=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --api-key)
      if [ -n "\${2:-}" ] && [ "\${2#--}" = "\${2:-}" ]; then API_KEY="\$2"; shift 2
      else echo "No API key given."; exit 1; fi ;;
    *) shift ;;
  esac
done
AUTH=()
[ -n "\$API_KEY" ] && AUTH=(-H "Authorization: Bearer \$API_KEY")
curl -s "http://localhost:\$PORT/health" > /dev/null 2>&1 || { echo "Server is not running. Start it with: cgpu model serve"; exit 1; }
CODE=\$(curl -s -o /dev/null -w "%{http_code}" "\${AUTH[@]}" "http://localhost:\$PORT/v1/models" 2>/dev/null || echo 000)
if [ "\$CODE" = "401" ]; then
  echo "This server requires an API key. Re-run: cgpu bench --api-key <key>"
  exit 1
fi
START=\$(date +%s%N)
RESP=\$(curl -s "http://localhost:\$PORT/v1/chat/completions" -H "Content-Type: application/json" "\${AUTH[@]}" \\
  -d '{"model":"'\$MODEL'","messages":[{"role":"user","content":"Explain quantum entanglement in 3 sentences."}],"max_tokens":256,"temperature":0}')
MS=\$(( (\$(date +%s%N) - START) / 1000000 ))
TOK=\$(echo "\$RESP" | jq -r '.usage.completion_tokens // "?"')
echo "\$RESP" | jq -r '.choices[0].message.content // (.error.message? // .error? // "Error: unknown")'
echo "--- \${TOK} tokens in \${MS}ms"
[ "\$TOK" != "?" ] && [ "\$TOK" -gt 0 ] && echo "    \$(awk "BEGIN{printf \"%.1f\",\$TOK/(\$MS/1000)}") tok/s"
EOF
chmod +x "${CLI_DIR}/bench"
 
cat > "${CLI_DIR}/throughput" << EOF
#!/bin/bash
set -euo pipefail
source /opt/vllm/bin/activate
PORT=${PORT}; MODEL="${MODEL_DIR}"
curl -s "http://localhost:\$PORT/health" > /dev/null 2>&1 || { echo "Server is not running. Start it with: cgpu model serve"; exit 1; }
N=100; IL=128; OL=256; EXTRA=()
while [ \$# -gt 0 ]; do
  case "\$1" in
    -n) N="\$2"; shift 2 ;; --input-len) IL="\$2"; shift 2 ;; --output-len) OL="\$2"; shift 2 ;;
    --request-rate) EXTRA+=("--request-rate" "\$2"); shift 2 ;; -h|--help)
      echo "Usage: throughput [-n NUM] [--input-len N] [--output-len N] [--request-rate N]"; exit 0 ;;
    *) EXTRA+=("\$1"); shift ;;
  esac
done
vllm bench serve --model "\$MODEL" --base-url "http://localhost:\$PORT" \\
  --endpoint /v1/completions --num-prompts "\$N" \\
  --random-input-len "\$IL" --random-output-len "\$OL" "\${EXTRA[@]}"
EOF
chmod +x "${CLI_DIR}/throughput"
 
# cgpu dispatcher — single entrypoint that routes to the backing subcommand scripts
cat > "${INSTALL_DIR}/cgpu" << EOF
#!/bin/bash
CLI_DIR="${CLI_DIR}"
cmd="\${1:-}"
case "\$cmd" in
  chat|serve|bench|throughput|logs|model)
    if [ ! -x "\$CLI_DIR/\$cmd" ]; then
      echo "'cgpu \$cmd' is not available (no model installed yet)."
      exit 1
    fi
    shift
    exec "\$CLI_DIR/\$cmd" "\$@"
    ;;
  ""|-h|--help)
    echo "Usage: cgpu <command> [options]"
    echo ""
    echo "Commands:"
    echo "  chat [--system \"...\"] [--api-key <key>]       Interactive chat"
    echo "  serve [--daemon|--stop|--status] [--api-key <key>]   Low-level server (needs sudo)"
    echo "  bench [--api-key <key>]                       Single-request latency test"
    echo "  throughput [-n N] [--request-rate N]          Multi-request load test"
    echo "  logs [-f|-e|-a]                               View service logs"
    echo "  model list|serve|stop|delete|switch <name>    Manage models"
    echo ""
    echo "API key (optional): pass --api-key <key> to require 'Authorization: Bearer <key>'."
    echo "  A key value is required (errors otherwise). Applies to the current serve session"
    echo "  only -- never written to persistent disk; serve again without it to drop the key."
    ;;
  *)
    echo "Unknown command: \$cmd"
    echo "Run 'cgpu' for usage."
    exit 1
    ;;
esac
EOF
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
ExecStartPre=/usr/local/bin/vllm-warm-cache
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
    cat > "${CLI_DIR}/logs" << LOGEOF
#!/bin/bash
case "\${1:-}" in
  -f|--follow) journalctl -u vllm-${PREFIX}.service -f ;;
  -e|--errors) journalctl -u vllm-${PREFIX}.service -p err --no-pager -n 50 ;;
  -a|--all)    journalctl -u vllm-${PREFIX}.service --no-pager ;;
  *)
    echo "=== vllm-${PREFIX} service status ==="
    systemctl status vllm-${PREFIX}.service --no-pager 2>/dev/null || true
    echo ""
    echo "=== Last 30 log lines ==="
    journalctl -u vllm-${PREFIX}.service --no-pager -n 30
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
 
model_to_dir() {
  case "$1" in
    phi4)     echo "/usr/local/lib/phi-4" ;;
    deepseek) echo "/usr/local/lib/deepseek-r1-70b" ;;
    llama)    echo "/usr/local/lib/llama-3.3-70b" ;;
    qwen)     echo "/usr/local/lib/qwen2.5-72b" ;;
    *)        echo "" ;;
  esac
}
 
model_to_service() {
  case "$1" in
    phi4)     echo "vllm-phi4.service" ;;
    deepseek) echo "vllm-dsr1.service" ;;
    llama)    echo "vllm-llama.service" ;;
    qwen)     echo "vllm-qwen.service" ;;
    *)        echo "" ;;
  esac
}
 
dir_to_name() {
  case "$1" in
    /usr/local/lib/phi-4)          echo "phi4" ;;
    /usr/local/lib/deepseek-r1-70b) echo "deepseek" ;;
    /usr/local/lib/llama-3.3-70b)  echo "llama" ;;
    /usr/local/lib/qwen2.5-72b)    echo "qwen" ;;
    *)                              echo "unknown" ;;
  esac
}
 
find_installed_model() {
  for d in /usr/local/lib/phi-4 /usr/local/lib/deepseek-r1-70b /usr/local/lib/llama-3.3-70b /usr/local/lib/qwen2.5-72b; do
    if [ -d "$d" ]; then
      dir_to_name "$d"
      return
    fi
  done
  echo ""
}
 
stop_all_vllm() {
  for svc in /etc/systemd/system/vllm-*.service; do
    [ -f "$svc" ] || continue
    svc_name=$(basename "$svc")
    echo "Stopping $svc_name..."
    sudo systemctl stop "$svc_name" 2>/dev/null || true
    sudo systemctl disable "$svc_name" 2>/dev/null || true
    sudo rm -f "$svc"
  done
  sudo systemctl daemon-reload 2>/dev/null || true
 
  if pgrep -f "vllm.entrypoints" > /dev/null 2>&1; then
    echo "Stopping manual vLLM process..."
    sudo pkill -f "vllm.entrypoints" 2>/dev/null || true
    sleep 2
    sudo pkill -9 -f "VLLM::EngineCore" 2>/dev/null || true
    sudo pkill -9 -f "vllm.entrypoints" 2>/dev/null || true
  fi
 
  for pidfile in /var/run/*-serve.pid; do
    [ -f "$pidfile" ] && sudo kill "$(cat "$pidfile")" 2>/dev/null || true
    sudo rm -f "$pidfile"
  done
}
 
stop_model() {
  local target_dir="$1"
  local svc_name
  svc_name=$(model_to_service "$(dir_to_name "$target_dir")")
 
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
      sudo pkill -9 -f "VLLM::EngineCore" 2>/dev/null || true
      sudo pkill -9 -f "vllm.entrypoints" 2>/dev/null || true
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
    sudo pkill -9 -f "VLLM::EngineCore" 2>/dev/null || true
    sudo pkill -9 -f "vllm.entrypoints" 2>/dev/null || true
    echo -n "."
    sleep 2
  done
  echo ""
}
 
wait_for_health() {
  echo "Waiting for model to load..."
  for i in $(seq 1 480); do
    if curl -sf "http://localhost:8000/health" > /dev/null 2>&1; then
      echo ""
      return 0
    fi
    [ $((i % 6)) -eq 0 ] && echo " $((i*5))s elapsed..." || echo -n "."
    sleep 5
  done
  echo ""
  echo "Timeout. Check: cgpu logs -f"
  return 1
}
 
usage() {
  echo "Usage: cgpu model <command> [options]"
  echo ""
  echo "Commands:"
  echo "  list                                    Show installed models"
  echo "  serve [phi4|deepseek|llama|qwen] [--api-key <key>]   Start serving a model"
  echo "  stop                                    Stop the running model"
  echo "  delete [phi4|deepseek|llama|qwen]       Stop and delete a model"
  echo "  switch <phi4|deepseek|llama|qwen>       Stop current, download new model"
  echo ""
  echo "  --api-key <key>  require 'Authorization: Bearer <key>' on /v1/* for this session"
  echo "                   (a key value is required). Applies to this serve only --"
  echo "                   not written to disk; serving again without it drops the key."
  echo ""
  echo "Examples:"
  echo "  cgpu model list"
  echo "  cgpu model serve"
  echo "  cgpu model serve deepseek"
  echo "  cgpu model stop"
  echo "  cgpu model delete qwen"
  echo "  cgpu model switch llama"
}
 
cmd="${1:-}"
case "$cmd" in
 
  list)
    echo "=== Installed Models ==="
    found=0
    not_installed=()
    for d in /usr/local/lib/phi-4 /usr/local/lib/deepseek-r1-70b /usr/local/lib/llama-3.3-70b /usr/local/lib/qwen2.5-72b; do
      name=$(dir_to_name "$d")
      if [ -d "$d" ]; then
        size=$(du -sh "$d" 2>/dev/null | cut -f1)
        status=""
        svc=$(model_to_service "$name")
        if [ -n "$svc" ] && systemctl is-active "$svc" > /dev/null 2>&1; then
          status="  [serving via systemd]"
        elif pgrep -af "vllm.entrypoints.*--model $d" > /dev/null 2>&1; then
          status="  [serving manually]"
        fi
        echo "  $name  ($size)  $d$status"
        found=$((found + 1))
      else
        not_installed+=("$name")
      fi
    done
    if [ "$found" -eq 0 ]; then
      echo "  No models installed"
    fi
    if [ ${#not_installed[@]} -gt 0 ]; then
      echo ""
      echo "=== Not Installed ==="
      echo "  ${not_installed[*]}"
      echo ""
      echo "  To install one of these, run:"
      for m in "${not_installed[@]}"; do
        echo "    cgpu model switch $m"
      done
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
      target=$(find_installed_model)
    fi
 
    if [ -z "$target" ]; then
      echo "No model installed. Run: cgpu model switch <phi4|deepseek|llama|qwen>"
      exit 1
    fi
 
    target_dir=$(model_to_dir "$target")
    if [ -z "$target_dir" ]; then
      echo "Unknown model: $target. Valid: phi4, deepseek, llama, qwen"
      exit 1
    fi
    if [ ! -d "$target_dir" ]; then
      echo "Model $target not installed ($target_dir not found)."
      echo "Run: cgpu model switch $target"
      exit 1
    fi
 
    target_svc=$(model_to_service "$target")
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

    # Stop anything else running
    stop_all_vllm
    wait_for_gpu_clear
 
    # Install service if missing
    if [ ! -f "/etc/systemd/system/$target_svc" ]; then
      echo "Creating systemd service for $target..."
      sudo bash /usr/local/lib/utilities-launch-vllm.sh \
        --model "$target" --install-to-service --skip-prewarm
    fi
 
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
 
    echo "Starting $target..."
    sudo systemctl start "$target_svc"
    if wait_for_health; then
      echo "$target is serving on http://localhost:8000/v1"
    fi
    ;;
 
  stop)
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
    target_dir=""

    if [ -n "$target" ]; then
      target_dir=$(model_to_dir "$target")
      if [ -z "$target_dir" ]; then
        echo "Unknown model: $target. Valid: phi4, deepseek, llama, qwen"
        exit 1
      fi
      if [ ! -d "$target_dir" ]; then
        echo "Model $target is not installed ($target_dir not found)."
        exit 1
      fi
    else
      installed=()
      for d in /usr/local/lib/phi-4 /usr/local/lib/deepseek-r1-70b /usr/local/lib/llama-3.3-70b /usr/local/lib/qwen2.5-72b; do
        [ -d "$d" ] && installed+=("$d")
      done
      if [ ${#installed[@]} -eq 0 ]; then
        echo "No models installed."
        exit 1
      elif [ ${#installed[@]} -eq 1 ]; then
        target_dir="${installed[0]}"
        echo "Found one model: $(dir_to_name "$target_dir")"
      else
        echo "Multiple models installed. Specify which one:"
        for d in "${installed[@]}"; do
          echo "  cgpu model delete $(dir_to_name "$d")"
        done
        exit 1
      fi
    fi
 
    stop_model "$target_dir"
 
    echo "Deleting model weights at $target_dir..."
    sudo rm -rf "$target_dir"
    echo "Deleted $(dir_to_name "$target_dir")."
    ;;
 
  switch)
    new_model="${2:-}"
    if [ -z "$new_model" ]; then
      echo "Usage: cgpu model switch <phi4|deepseek|llama|qwen>"; exit 1
    fi

    new_svc=$(model_to_service "$new_model")
    if [ -z "$new_svc" ]; then
      echo "Unknown model: $new_model. Valid: phi4, deepseek, llama, qwen"
      exit 1
    fi
 
    stop_all_vllm
 
    # Clear shared vLLM graph cache
    sudo rm -rf /var/cache/vllm-compile/rank_0_0 2>/dev/null || true
    sudo rm -rf /var/cache/vllm-compile/torch_aot 2>/dev/null || true
    sudo mkdir -p /var/cache/vllm-compile/torch_aot
    echo "Cleared vLLM graph cache."
 
    wait_for_gpu_clear

    echo "Installing $new_model (this will take 10-20 minutes depending on model size)..."
    INSTALL_T0=$(date +%s)
    sudo bash /usr/local/lib/utilities-launch-vllm.sh \
      --model "$new_model" --install-to-service --skip-prewarm
    INSTALL_ELAPSED=$(( $(date +%s) - INSTALL_T0 ))
    echo "Install (download + setup) complete in ${INSTALL_ELAPSED}s."

    # Start the correct service by name
    echo "Starting $new_model service..."
    LOAD_T0=$(date +%s)
    sudo systemctl start "$new_svc"
    if wait_for_health; then
      LOAD_ELAPSED=$(( $(date +%s) - LOAD_T0 ))
      echo "Model loaded and ready in ${LOAD_ELAPSED}s. Launching chat..."
      exec chat
    fi
    ;;
 
  *)
    usage; exit 0 ;;
esac
MODELEOF
    chmod +x "${CLI_DIR}/model"
fi
 
# motd
cat > /etc/motd << EOF

 🚀 ${DISPLAY_NAME} CGPU VM -- Ready
 -----------------------------------------
 💬 cgpu chat${SYS_PROMPT:+ [--system "..."]}
 ▶️ cgpu serve [--daemon|--stop|--status]  (needs sudo)
 ⚡ cgpu bench
 📊 cgpu throughput [-n 100] [--request-rate 50]
 📜 cgpu logs [-f|--follow] [-e|--errors]
 🔧 cgpu model list|serve|stop|delete|switch <phi4|deepseek|llama|qwen>
 🔑 Optional auth: cgpu model serve --api-key <key> (this session only)

 ⚙️  Service:  sudo systemctl status vllm-${PREFIX}
 🌐 API:      http://localhost:${PORT}/v1
 🧠 Model:    ${MODEL_DIR}
 🐍 venv:     /opt/vllm
 💾 Cache:    ${COMPILE_CACHE_DIR}
 ⚡ Inductor: ${INDUCTOR_CACHE_DIR}

EOF
 
echo "============================================"
echo "  ${DISPLAY_NAME} installation complete!"
if [ "$INSTALL_SERVICE" = true ]; then
    echo "  Systemd service: enabled (auto-start on boot)"
    echo "  Compile cache:   ${COMPILE_CACHE_DIR}"
    echo "  Inductor cache:  ${INDUCTOR_CACHE_DIR}"
    echo "  Manual: sudo systemctl start vllm-${PREFIX}"
fi
echo "============================================"
 
