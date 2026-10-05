# NVIDIA GPU Attestation Verifier Preview

This folder contains the build-time dependencies and policy for the optional `nvattest` preview utility. The utility builds NVIDIA's new local GPU attestation verifier and then runs it directly on the VM. For upstream information, see [NVIDIA/attestation-sdk](https://github.com/NVIDIA/attestation-sdk/).

## Why migrate to nvattest?

Local GPU attestation is moving from the existing Python-based `local_gpu_verifier` to NVIDIA's `nvattest` CLI. The existing Python-based verifier is being deprecated soon. If your workflows currently depend on it, begin testing the new verifier and planning migration now. This utility is just an optional preview for now - running it does not automatically replace the existing `gpu-attestation` command.

## Prerequisites

- Complete core onboarding on an H100 CGPU VM, with the NVIDIA GPU driver installed and confidential computing enabled.
- Install Docker using [../step-3-install-gpu-tools.sh](../step-3-install-gpu-tools.sh), if it is not already available.

## Usage

To test the new nv-attest verifier, from the `src` folder, run:

```bash
sudo bash utilities-nv-attest-verifier.sh
```

The first run builds `nvattest` from NVIDIA's current `main` branch. Later runs reuse the installed binary and run attestation again without pulling or building Docker images.

To build a fresh verifier from the latest upstream sources, use `--rebuild`:

```bash
sudo bash utilities-nv-attest-verifier.sh --rebuild
```

Please note that a fresh build can take up to 5 minutes.

## Expected success and troubleshooting

After successful GPU attestation, both fresh-build and reuse runs should finish with:

```text
GPU Attestation is Successful.
```

The verifier binary and logs are retained on the VM at:

```text
/usr/local/lib/new_local_gpu_verifier/nvattest
/usr/local/lib/new_local_gpu_verifier/build.log
/usr/local/lib/new_local_gpu_verifier/attestation.log
```

## Docker image and cleanup

The build uses the official `rust:1.98.1-slim-bookworm` image, based on Debian 12 Bookworm and pinned by SHA-256 digest in [Dockerfile](Dockerfile). This image contains the Rust toolchain to which the Dockerfile adds additional C++ build tools and dependency libraries. Attestation then uses the driver already installed on the VM.

The final `scratch` image contains only the `nvattest` binary, which the utility exports to the VM. After the build/export, and before running attestation, the script attempts to remove:

- The temporary export container.
- The generated build image.
- The pulled Rust base image.
- The temporary build-context directory.

The binary and logs remain available for later runs while no verifier container is kept running.

## Support files and policy

- [Dockerfile](Dockerfile) provides the disposable build environment.
- [attestation-sdk-ocsp-sha384.patch](attestation-sdk-ocsp-sha384.patch) enables SHA-384 OCSP certificate identifiers for Azure THIM.
- [azure_cgpu_h100_default_policy.rego](azure_cgpu_h100_default_policy.rego) is the Azure CGPU relying-party policy, derived from NVIDIA's [`allow_trust_outpost_ocsp.rego`](https://github.com/NVIDIA/attestation-sdk/blob/main/relying_party_policy_examples/allow_trust_outpost_ocsp.rego). This policy intentionally removes the OCSP nonce-match requirement for cached responses, which is a security-relevant behavior and differs from NVIDIA's default policy.
