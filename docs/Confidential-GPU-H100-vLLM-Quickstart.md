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

| Model Family | Provider | Model Id from Hugging Face | Download size |
|-------|----------|-----------------|---------------|
| `phi` | Microsoft | `microsoft/phi-4` | ~30 GB |
| `llama` | Meta | `RedHatAI/Llama-3.3-70B-Instruct-FP8-dynamic` | ~70 GB |
| `deepseek` | DeepSeek | `RedHatAI/DeepSeek-R1-Distill-Llama-70B-FP8-dynamic` | ~70 GB |
| `qwen` | Alibaba Cloud | `RedHatAI/Qwen2.5-72B-Instruct-FP8-dynamic` | ~70 GB |
| `qwen` | Alibaba Cloud | `Qwen/Qwen3.8-27B` | ~70 GB |


These are example models that Microsoft sampled and enabled as examples for the sample vLLM onboarding workflow;.Model weights are downloaded from third-party sources such as Hugging Face, and each model is provided by its respective third-party provider.

You can switch models at any time using the `cgpu model switch <model-id>` command. The command installs the selected model if necessary, stops the current service, starts the new model service, waits for it to become healthy, and then opens chat. You do **not** need to run `cgpu model serve` afterward. For per-model specifications, see [vLLM Model Details](Confidential-GPU-H100-vLLM-Models.md).

Model use is subject to the respective model provider's license terms. Customers are responsible for obtaining any required permissions and accepting applicable licenses before downloading model weights.
---

## Install

### Prepare the Onboarding Package
If you created the VM from a VMI, the onboarding package `cgpu-onboarding-package.tar.gz` is not included.

Download the latest release package directly on the VM:

```bash
curl -LO https://github.com/Azure/az-cgpu-onboarding/releases/latest/download/cgpu-onboarding-package.tar.gz
```

Alternatively, download `cgpu-onboarding-package.tar.gz` from the [latest az-cgpu-onboarding release Github page](https://github.com/Azure/az-cgpu-onboarding/releases/latest) and upload it to the VM:

```bash
scp -i <private-key-path> cgpu-onboarding-package.tar.gz <admin-username>@<vm-public-ip>:~
```

### Install the Model
After you have it ready, SSH into the VM and extract the uploaded package:

```bash
ssh -i <private-key-path> <admin-username>@<vm-public-ip>
tar -xzf ~/cgpu-onboarding-package.tar.gz -C ~
```

If you used an onboarding-script flow, the package is already present. From the VM, install your selected model by Hugging Face model ID (case-insensitive):

```bash
cd ~/cgpu-onboarding-package/
sudo bash step-4-install-vllm-preview.sh --model-id microsoft/phi-4
```

For example, to install Qwen3.8-27B:

```bash
sudo bash step-4-install-vllm-preview.sh --model-id qwen/qwen3.8-27b --api-key sk-xxxx   # [optional]
```

The script will:

1. Create a Python venv at `/opt/vllm` and install vLLM
2. Download model weights from Hugging Face to `/usr/local/lib/<organization>/<repository>/` (e.g. `/usr/local/lib/microsoft/phi-4/`, `/usr/local/lib/qwen/qwen3.8-27b`)
3. Install a `cgpu` CLI with subcommands: `cgpu chat`, `cgpu serve`, `cgpu bench`, `cgpu throughput`, `cgpu logs`, `cgpu model`
4. Register a systemd service (e.g. `vllm-microsoft--phi-4.service`, `vllm-qwen--qwen3.8-27b.service`) that auto-starts on reboot

**Expected download time:**

| Model Id | Download size | Typical time |
|----------|--------------|--------------|
| `microsoft/phi-4` | ~30 GB | 5–10 min |
| `Qwen/Qwen3.8-27B` | ~52 GB | 10–20 min |
| `RedHatAI/Qwen2.5-72B-Instruct-FP8-dynamic` | ~70 GB | 15–30 min |
| `RedHatAI/Llama-3.3-70B-Instruct-FP8-dynamic` | ~70 GB | 15–30 min |
| `RedHatAI/DeepSeek-R1-Distill-Llama-70B-FP8-dynamic` | ~70 GB | 15–30 min |

---

## Verification

The vLLM server must be running before any `http://localhost:8000` command will work.

To confirm it is up, run:

```bash
cgpu model serve microsoft/phi-4
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

> This requires the vLLM service to be running (see [Verification](#verification)). If you get `curl: Connection refused`, the model isn't up yet — start it with `cgpu model serve <model-id>` and check `cgpu logs -f`.

**Step 1 — find the model ID.** The vLLM registers the model under the on-disk weights path it was launched with (for example `/usr/local/lib/microsoft/phi-4`). Requests must use that exact ID, so query the server for it first:

```bash
curl -s http://localhost:8000/v1/models | jq -r '.data[].id'
# e.g. /usr/local/lib/microsoft/phi-4
```

**Step 2 — call the chat endpoint.** Pass the ID from step 1 as the `"model"` field:

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/usr/local/lib/microsoft/phi-4",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

Replace `/usr/local/lib/microsoft/phi-4` with whatever `/v1/models` reports for your installed model.

---

## Command Reference

All functionality is exposed through the single `cgpu` command. Run `cgpu` with no arguments to see this list on the VM.

| Command | What it does |
|---------|-------------|
| `cgpu chat` | Interactive chat in your terminal |
| `cgpu chat --system "..."` | Chat with a custom system prompt |
| `cgpu model serve <model-id>` | **Recommended** way to start/restart a model. If the model is not installed, installs it first; otherwise starts the existing managed systemd service. Run as your normal user. |
| `cgpu model list` | List every installed model, its on-disk size, and which one is currently serving |
| `cgpu model stop` | Stop the running model and free its GPU memory (weights stay on disk) |
| `cgpu model switch <model-id>` | Switch to the specified model. If it is already installed, reuse its existing weights and service; otherwise install it first. Then start it, wait until it is ready, and open chat. |
| `cgpu model delete <model-id>` | Stop the specified model and delete its weights from disk to reclaim space |
| `cgpu logs` | Service status + the last 30 log lines. Start here. |
| `cgpu logs -f` | Follow live output — use while the model is loading or to watch requests in real time (Ctrl-C to stop) |
| `cgpu logs -e` | Errors only — the last 50 error-priority lines; use first when the model won't start |
| `cgpu logs -a` | The complete journal for the service — full history for deep debugging (pipe to `less`) |
| `cgpu bench` | Single-request latency and tokens/sec test |
| `cgpu throughput [-n N] [--request-rate N] [--api-key <key>]` | Multi-request load test. `-n N` sets the total number of requests (default: 100). `--request-rate N` limits how many requests are submitted per second; omit it to submit requests as quickly as possible. |
| `sudo cgpu serve <model-id>` | Low-level: start an installed model in the foreground (requires `sudo`) |
| `sudo cgpu serve <model-id> --daemon` | Low-level: start an installed model in the background (requires `sudo`) |
| `sudo cgpu serve --stop` | Stop the background `cgpu serve` process |
| `sudo cgpu serve --status` | Show background `cgpu serve` process status |
| `--api-key <key>` | Require bearer-token auth for the **current serve session only** (not written to persistent disk). Accepted by `model serve`, `chat`, `bench`, `throughput`, and low-level `serve`. A key value is required. See [VLLM official documents](https://docs.vllm.ai/en/stable/getting_started/quickstart/#online-serving). |

> **Tip:** For everyday use, prefer `cgpu model serve <model-id>` — it validates the model, installs it if needed, clears the GPU, and manages the systemd service for you. The low-level `sudo cgpu serve <model-id>` (foreground / `--daemon`) is only for quick manual debugging and needs `sudo`.

### Throughput options

- `-n N` controls the total number of benchmark requests, not the number of requests per second. For example, `-n 200` runs 200 requests.
- `--request-rate N` controls the request arrival rate in requests per second. For example, `--request-rate 10` submits approximately 10 requests per second. If omitted, the benchmark submits requests without a rate limit.
- The benchmark defaults to random inputs of 128 tokens and random outputs of 256 tokens. Use `--input-len N` and `--output-len N` to change those lengths.

### Troubleshooting

| Symptom | Try |
|---------|-----|
| `cgpu chat` says "Service not found" | Run `cgpu model serve <model-id>` |
| `/health` returns nothing | `cgpu logs -f` — model may still be loading |
| Model fails to start | `cgpu logs -e`; check `nvidia-smi` for GPU availability |
| `curl: Connection refused` | `sudo systemctl status vllm-<model-id>.service` (e.g. `vllm-microsoft--phi-4.service`, `vllm-qwen--qwen3.8-27b.service`) |
