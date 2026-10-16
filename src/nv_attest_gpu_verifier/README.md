# NVIDIA GPU Attestation Verifier Preview

This folder contains the build-time dependencies and policy for the `nvattest` verifier. The utility script builds NVIDIA's new local GPU attestation verifier and then runs it directly on the VM. For upstream information, see [NVIDIA/attestation-sdk](https://github.com/NVIDIA/attestation-sdk/).

## Why migrate to nvattest?

Local GPU attestation is moving from the existing Python-based `local_gpu_verifier` to NVIDIA's `nvattest` CLI. The existing Python-based verifier is being deprecated soon. If your workflows currently depend on it, begin testing the new verifier and planning migration now. This utility is just an optional preview for now - running it does not affect the existing `gpu-attestation` command.

## Prerequisites

- Complete core onboarding on an H100 CGPU VM, with the NVIDIA GPU driver installed and confidential computing enabled
- Install Docker using [../step-3-install-gpu-tools.sh](../step-3-install-gpu-tools.sh), if it is not already available

## Usage

To test the new nv-attest verifier, from the `src` folder, run:

```bash
sudo bash utilities-nv-attest-verifier.sh
```

The script automatically detects Ubuntu 22.04 or 24.04 and selects the corresponding build image. The first run builds `nvattest` from NVIDIA's release branch and creates a local binary. Later runs reuse that installed binary and run attestation again without pulling or building Docker images.

To build a fresh verifier, use `--rebuild`:

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

The following defaults are selected for the guest OS to use for building the verifier:

- Ubuntu 22.04: [Dockerfile.bullseye](Dockerfile.bullseye), using `mcr.microsoft.com/devcontainers/rust:2.0.16-bullseye`.
- Ubuntu 24.04: [Dockerfile.azlinux3](Dockerfile.azlinux3), using `mcr.microsoft.com/azurelinux/base/rust:1.96.1-2-azl3.0.20261005`.

Both container image projects are open source. Customers can review their public upstream build definitions:

- [Devcontainers Rust source Dockerfile](https://github.com/devcontainers/images/blob/e2b8a60b1f0c1ea4b4f7e6ef5e1b92897045d2ec/src/rust/.devcontainer/Dockerfile).
- [Azure Linux 3 Rust source Dockerfile](https://github.com/microsoft/azurelinux/blob/a526a629b8ff3db2ec8a9633803506bd61118bca/.pipelines/containerSourceData/rust/Dockerfile-Rust).

The utility exports only the `nvattest` binary from the disposable builder image to the VM. After the build/export, and before running attestation, the script will remove:

- The temporary export container
- The generated build image
- The pulled selected Rust base image
- The temporary build-context directory

The binary and logs remain available for later runs while no verifier container is kept running.

## Support files and policy

- [Dockerfile.bullseye](Dockerfile.bullseye) and [Dockerfile.azlinux3](Dockerfile.azlinux3) provide the OS-specific disposable build environments.
- The utility selects SHA-384 OCSP request and response-matching certificate identifiers through NVIDIA's native `--ocsp-cert-id-hash sha-384` option for both THIM and NVIDIA OCSP.
- [azure_cgpu_h100_default_policy.rego](azure_cgpu_h100_default_policy.rego) is the Azure CGPU relying-party policy, derived from NVIDIA's [`allow_trust_outpost_ocsp.rego`](https://github.com/NVIDIA/attestation-sdk/blob/main/relying_party_policy_examples/allow_trust_outpost_ocsp.rego). This policy intentionally removes the OCSP nonce-match requirement for cached responses, which is a security-relevant behavior and differs from NVIDIA's default policy.
