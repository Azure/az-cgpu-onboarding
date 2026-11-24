# NVIDIA GPU Attestation Verifier

This folder contains the build support files and policy for NVIDIA's C++ `nvattest` verifier, the default GPU verifier used by [step-2-attestation.sh](../step-2-attestation.sh) in updated NCC H100 onboarding packages for Ubuntu 22.04 and 24.04. The verifier runs directly on the VM after a disposable Docker build. For upstream information, see [NVIDIA/attestation-sdk](https://github.com/NVIDIA/attestation-sdk/).


## Prerequisites

- Complete step 1 on an NCC H100 VM running Ubuntu 22.04 or 24.04, with the NVIDIA driver installed and confidential computing enabled.
- Docker is required to build `nvattest` (first run or `--rebuild-nvattest`), not for binary reuse.

## Usage

From the extracted updated onboarding package in the VM (or the repository's `src` directory), run:

```bash
sudo bash step-2-attestation.sh
```

Step 2 runs both CPU and GPU attestation by default; it also accepts `--cpu-only`, `--gpu-only`, `--install-to-usr-local`, and `--rebuild-nvattest`. 

For later GPU attestation, run `sudo gpu-attestation`. To build the verifier without running attestation, run:

```bash
sudo bash utilities-build-nvattest-verifier.sh [output_dir]
```

The utility always builds `nvattest` from NVIDIA's release branch into `output_dir` (default: the script's folder). Step 2 builds it into `/usr/local/lib/new_local_gpu_verifier` only when the binary is missing or `--rebuild-nvattest` is passed. Step 2 and `gpu-attestation` own region detection, THIM selection, and attestation; the installed command runs without Docker or the build utility.

To build a fresh verifier and attest, run:

```bash
sudo bash step-2-attestation.sh --gpu-only --rebuild-nvattest
```

Please note that a fresh build can take several minutes, or longer if transient downloads need retries.

## Switching to or from the previous Python verifier

There is no automatic Python fallback if `nvattest` fails. The new `gpu-attestation` command does not provide the previous Python-specific arguments or token format.

From the extracted updated package in the VM, explicitly select the previous Python GPU verifier with:

```bash
sudo bash utilities-legacy-local-gpu-verifier.sh
```

This runs Python GPU attestation locally without changing `gpu-attestation`. To install or refresh the default `nvattest` command, run the root step 2:

```bash
sudo bash step-2-attestation.sh --gpu-only
```

See [legacy usage](../legacy_local_gpu_verifier/README.md). The nvattest utility only builds/rebuilds; use step 2 to install or refresh the command alias and attest.

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

- The temporary export container.
- The generated build image.
- The pulled Microsoft Ubuntu base image.
- The temporary build-context directory.

The binary and logs remain available for later runs while no verifier container is kept running.

## Support files and policy

- [Dockerfile.bullseye](Dockerfile.bullseye) and [Dockerfile.azlinux3](Dockerfile.azlinux3) provide the OS-specific disposable build environments.
- Step 2 selects SHA-384 OCSP request and response-matching certificate identifiers through NVIDIA's native `--ocsp-cert-id-hash sha-384` option for both THIM and NVIDIA OCSP.
- [azure_cgpu_h100_default_policy.rego](azure_cgpu_h100_default_policy.rego) is the Azure CGPU relying-party policy, derived from NVIDIA's [`allow_trust_outpost_ocsp.rego`](https://github.com/NVIDIA/attestation-sdk/blob/main/relying_party_policy_examples/allow_trust_outpost_ocsp.rego). This policy intentionally removes the OCSP nonce-match requirement for cached responses, which is a security-relevant behavior and differs from NVIDIA's default policy.
