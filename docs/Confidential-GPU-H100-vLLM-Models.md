# Confidential GPU — vLLM Model Details

This page describes example models that have been tested with the sample vLLM onboarding workflow on `Standard_NCC40ads_H100_v5`. These models are provided as examples only and are not officially supported or endorsed by Microsoft. Model weights are downloaded from third-party sources such as Hugging Face.

Model capabilities, quality benchmarks, and licensing are published by each model's provider.

For installation instructions, see the [vLLM Quickstart](Confidential-GPU-H100-vLLM-Quickstart.md).

---

## Contents

- [Model Specifications](#model-specifications)
- [Precision and Quantization](#precision-and-quantization)
- [Optimizations](#optimizations)

---

## Model Specifications

| Key | Model | Hugging Face ID | Weights | Params | vLLM serve args |
|-----|-------|-----------------|---------|--------|-----------------|
| `phi4` | Microsoft Phi-4 | `microsoft/phi-4` | ~30 GB | 14B | `--max-model-len 16384 --trust-remote-code` |
| `deepseek` | DeepSeek R1 Distill Llama 70B | `RedHatAI/DeepSeek-R1-Distill-Llama-70B-FP8-dynamic` | ~70 GB | 70B | `--gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256` |
| `llama` | Llama 3.3 70B Instruct | `RedHatAI/Llama-3.3-70B-Instruct-FP8-dynamic` | ~70 GB | 70B | `--gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256` |
| `qwen` | Qwen 2.5 72B Instruct | `RedHatAI/Qwen2.5-72B-Instruct-FP8-dynamic` | ~70 GB | 72B | `--gpu-memory-utilization 0.85 --kv-cache-dtype fp8 --max-num-seqs 256` |

All 70B models use pre-quantized FP8 weights from RedHatAI, so no runtime quantization is required. FP8 weights are approximately 50% smaller than the FP16 equivalents.

---

## Precision and Quantization

FP8 quantization is required to fit 70B models on a single H100:

| Precision | 70B weights size | Single H100 fit |
|-----------|-----------------|-----------------|
| FP16 (full) | ~140 GB | No — exceeds 94 GB VRAM |
| FP8 | ~70 GB | Yes — ~10–24 GB headroom for KV cache |

The FP8 variants used here are sourced from RedHatAI's pre-quantized distributions. Quantization was applied offline — there is no runtime quantization overhead on your VM.

---

## Optimizations

This section describes the specific optimizations applied to make these models fit into a single H100 CGPU VM.

### Fitting a 70B model into a single H100

| Optimization | What it does | Effect |
|--------------|--------------|--------|
| **FP8 weights** (RedHatAI pre-quantized) | Stores model weights at FP8 instead of FP16 | 70B weights drop from ~140 GB to ~70 GB, which fits within the 94 GB H100 VRAM |
| **`--kv-cache-dtype fp8`** | Stores the KV cache at FP8 | Reduces KV cache memory, leaving room for larger batch sizes and longer contexts within the remaining ~10–24 GB |
| **`--gpu-memory-utilization 0.85`** | Caps vLLM's VRAM allocation at 85% | Reserves headroom so the model and KV cache do not exceed physical VRAM |
| **Grouped Query Attention (GQA), 8 KV heads** | Inherent to the model architecture (all three 70B models) | Reduces KV cache memory ~8× versus standard multi-head attention |

Without FP8, a 70B model at FP16 requires ~140 GB of weights alone and cannot load on a single H100. FP8 weights plus an FP8 KV cache are what make single-H100 serving possible.
