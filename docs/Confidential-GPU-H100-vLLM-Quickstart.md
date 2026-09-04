# [Preview] Confidential GPU — vLLM Quickstart

This quickstart provides a reference example for running a large language model locally on an Azure Confidential GPU VM (`Standard_NCC40ads_H100_v5`). The model and vLLM server run within the VM’s hardware-based Trusted Execution Environment (TEE).

When the API endpoint is accessible only from within the VM, inference requests and responses remain within its protected boundary. If you expose the endpoint externally, the data crosses that boundary, and you are responsible for securing the connection and access to the API.

> **This step is optional.** First, deploy and verify a working CGPU VM using the Bash, PowerShell, or VMI flow. Then return to this guide when you are ready to explore LLM inference.

---

## Contents

- [Prerequisites](#prerequisites)
- [Pick a Model](#pick-a-model)
- [Install](#install)
- [Verification](#verification)
- [Talk to the Model](#talk-to-the-model)
- [Command Reference](#command-reference)

---

## Prerequisites

- **Supported OS** — Ubuntu 22.04 and 24.04.
- **Step 1** complete — GPU driver installed
- **Step 2** complete — **Attestation passed.** 
  - Run the following on the VM to confirm both CPU and GPU attestation succeed:
    ```bash
    sudo cpu-attestation
    sudo gpu-attestation
    ```
- **Step 3** complete — Docker and NVIDIA Container Toolkit installed
- **Disk space** — the model weights plus vLLM cache for the 70B models need a **128 GB or larger** OS disk (or attach a data disk): allow ~50 GB free for Phi-4 and ~90 GB free for the 70B models, plus headroom for the compile cache.
  - Check free space on the root filesystem with:
    ```bash
    df -h /
    ```
    The Avail column shows the free space available for the model download.

---

## Pick a Model

| Model | Provider | Hugging Face ID | Download size |
|-------|----------|-----------------|---------------|
| `phi4` | Microsoft | `microsoft/phi-4` | ~30 GB |
| `llama` | Meta | `RedHatAI/Llama-3.3-70B-Instruct-FP8-dynamic` | ~70 GB |
| `deepseek` | DeepSeek | `RedHatAI/DeepSeek-R1-Distill-Llama-70B-FP8-dynamic` | ~70 GB |
| `qwen` | Alibaba Cloud | `RedHatAI/Qwen2.5-72B-Instruct-FP8-dynamic` | ~70 GB |

The models listed in this guide are included solely as examples for the sample vLLM onboarding workflow. Their inclusion does not constitute Microsoft endorsement or indicate official Microsoft support. Model weights are downloaded from third-party sources, such as Hugging Face, and are subject to the terms and licenses of their respective providers.

You can switch between installed models at any time using the `cgpu model switch` command. For per-model specifications, see [vLLM Model Details](Confidential-GPU-H100-vLLM-Models.md).

Model use is subject to the respective model provider's license terms. Customers are responsible for obtaining any required permissions and accepting applicable licenses before downloading model weights.
---

## Install

To install on your CGPU VM, first SSH in and then run:

```bash
cd cgpu-onboarding-package/
sudo bash step-4-install-vllm-preview.sh --model phi4
```

Replace `phi4` with your chosen model name. To require an API key from the start, add the optional `--api-key <key>` flag

```bash
sudo bash step-4-install-vllm-preview.sh --model phi4 --api-key sk-xxxx   # [optional]
```

The script will:

1. Create a Python venv at `/opt/vllm` and install vLLM
2. Download model weights from Hugging Face to `/usr/local/lib/{model}/` (e.g. `/usr/local/lib/phi-4/`)
3. Install a `cgpu` CLI with subcommands: `cgpu chat`, `cgpu serve`, `cgpu bench`, `cgpu throughput`, `cgpu logs`, `cgpu model`
4. Register a systemd service (e.g. `vllm-phi4.service`) that auto-starts on reboot

**Expected download time:**

| Model | Download size | Typical time |
|-------|--------------|--------------|
| `phi4` | ~30 GB | 5–10 min |
| `llama`, `deepseek`, `qwen` | ~70 GB | 15–30 min |

---

## Verification

The vLLM server must be running before any `http://localhost:8000` command will work.

To confirm it is up, run:

```bash
cgpu model serve 
```

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/health
```

A `200` response means the model is loaded and ready. If it is still starting up you can follow the progress:

```bash
cgpu logs -f    # follow live startup logs
```

---

## Talk to the Model

### Interactive chat

```bash
cgpu chat
```

Type your message and press Enter. Use `/clear` to reset the conversation, `/quit` to exit.

```bash
cgpu chat --system "You are a Python expert. Be concise."
```

### OpenAI-compatible API

vLLM serves an endpoint at `http://localhost:8000/v1` that speaks the same request/response format as the OpenAI API. This lets you reuse the entire OpenAI ecosystem — the official `openai` Python/JS SDKs, LangChain, LlamaIndex, and most LLM tooling — against your local, confidential model.

Common uses:
- Point an existing OpenAI app at your VM by setting the base URL to `http://localhost:8000/v1`.
- Build scripts or services on the VM that call the model over HTTP instead of the interactive `cgpu chat`.

> This requires the vLLM service to be running (see [Verification](#verification)). If you get `curl: Connection refused`, the model isn't up yet — start it with `cgpu model serve` and check `cgpu logs -f`.

**Step 1 — find the model ID.** The vLLM registers the model under the on-disk weights path it was launched with (for example `/usr/local/lib/phi-4`). Requests must use that exact ID, so query the server for it first:

```bash
curl -s http://localhost:8000/v1/models | jq -r '.data[].id'
# e.g. /usr/local/lib/phi-4
```

**Step 2 — call the chat endpoint.** Pass the ID from step 1 as the `"model"` field:

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/usr/local/lib/phi-4",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

Replace `/usr/local/lib/phi-4` with whatever `/v1/models` reports for your installed model.

> If you started the server with an API key, add `-H "Authorization: Bearer <key>"` to these requests — without it they return `401`.

---

## Command Reference

All functionality is exposed through the single `cgpu` command. Run `cgpu` with no arguments to see this list on the VM.

| Command | What it does |
|---------|-------------|
| `cgpu chat` | Interactive chat in your terminal |
| `cgpu chat --system "..."` | Chat with a custom system prompt |
| `cgpu model serve` | **Recommended** way to start/restart the model. Validates the model, clears the GPU, and starts it as a managed systemd service (auto-restarts on reboot). Run as your normal user. |
| `cgpu model serve <name>` | Start a specific installed model (`phi4`, `deepseek`, `llama`, `qwen`) |
| `cgpu model list` | List every installed model, its on-disk size, and which one is currently serving |
| `cgpu model stop` | Stop the running model and free its GPU memory (weights stay on disk) |
| `cgpu model switch <name>` | Stop the current model, download+install a different one, then start it. Downloads new weights before stopping the old model — expect 15–30 min for 70B models. |
| `cgpu model delete <name>` | Stop the named model and delete its weights from disk to reclaim space |
| `cgpu logs` | Service status + the last 30 log lines. Start here. |
| `cgpu logs -f` | Follow live output — use while the model is loading or to watch requests in real time (Ctrl-C to stop) |
| `cgpu logs -e` | Errors only — the last 50 error-priority lines; use first when the model won't start |
| `cgpu logs -a` | The complete journal for the service — full history for deep debugging (pipe to `less`) |
| `cgpu bench` | Single-request latency and tokens/sec test |
| `cgpu throughput [-n N] [--request-rate N]` | Multi-request load test |
| `sudo cgpu serve` | Low-level: start vLLM server in the foreground (requires `sudo`) |
| `sudo cgpu serve --daemon` | Low-level: start vLLM server in the background (requires `sudo`) |
| `sudo cgpu serve --stop` | Stop the background `cgpu serve` process |
| `--api-key <key>` | Require bearer-token auth for the **current serve session only** (not written to disk). Accepted by `model serve`, `chat`, `bench`, and low-level `serve`. Pass `--api-key` with no value to be prompted. See [VLLM official documents](https://docs.vllm.ai/en/stable/getting_started/quickstart/#online-serving). |

> **Tip:** For everyday use, prefer `cgpu model serve` — it validates the model, clears the GPU, and manages the systemd service for you. The low-level `sudo cgpu serve` (foreground / `--daemon`) is only for quick manual debugging and needs `sudo`.
To customize the LLM configuration, review and update the model arguments in utilities-launch-vllm.sh

### Troubleshooting

| Symptom | Try |
|---------|-----|
| `cgpu chat` says "Service not found" | Run `cgpu model serve` |
| `/health` returns nothing | `cgpu logs -f` — model may still be loading |
| Model fails to start | `cgpu logs -e`; check `nvidia-smi` for GPU availability |
| `curl: Connection refused` | `sudo systemctl status vllm-phi4.service` (replace `phi4` with your model) |
| `401 Unauthorized` on `/v1/*` | An API key is set on the server — resend the request with `-H "Authorization: Bearer <key>"` (or pass `--api-key` to the `cgpu` command). |
