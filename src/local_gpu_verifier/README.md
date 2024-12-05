- [Verifier](#verifier)
  - [System Requirements:](#system-requirements)
  - [Pre-requisites:](#pre-requisites)
  - [Install](#install)
    - [Step 1: Elevate to Root User Privileges (Optional)](#step-1-elevate-to-root-user-privileges-optional)
    - [Step 2: Create a new Python Virtual Environment](#step-2-create-a-new-python-virtual-environment)
    - [Step 3: Install and run Local GPU Verifier](#step-3-install-and-run-local-gpu-verifier)
    - [Troubleshooting Installation Issues](#troubleshooting-installation-issues)
  - [Usage](#usage)
  - [Module details:](#module-details)
    - [rim](#rim)
    - [attestation](#attestation)
    - [nvmlHandler](#nvmlhandler)
    - [verifier](#verifier-1)
    - [cc\_admin](#cc_admin)
  
# Verifier

The Verifier is a Python-based tool that validates GPU measurements by comparing an authenticated attestation report containing runtime measurements with authenticated golden measurements. Its purpose is to verify if the software and hardware state of the GPU are in accordance with the intended state.

## System Requirements:
- NVIDIA Hopper H100 GPU or newer
- GPU SKU with Confidential Compute(CC)
- NVIDIA GPU driver installed

## Pre-requisites:
   Requires Python 3.8 or later.

## Install

### Step 1: Elevate to Root User Privileges (Optional)

If you want the verifier to set the GPU Ready State based on the Attestation results, you will need to elevate the user privileges to root before you execute the rest of the instructions. For use cases where the user does not intend to set the GPU Ready State (e.g., when using the Attestation SDK), you can install and run the Verifier tool without requiring sudo privileges.

    sudo -i

### Step 2: Create a new Python Virtual Environment

    python3 -m venv  ./prodtest
    source ./prodtest/bin/activate

### Step 3: Install and run Local GPU Verifier

    cd local_gpu_verifier
    pip3 install .
    python3 -m verifier.cc_admin

### Troubleshooting Installation Issues

- If you encounter any pip related issues while building the package, please execute the following commands to update to the latest versions of setuptools and pip

        python3 -m pip install --upgrade setuptools
        pip install -U pip

- If you encounter any permission issues while building the package, please execute the following commands and then build the package again

        cd local_gpu_verifier
        rm -r build

## Usage
To run the cc_admin module, use the following command:

    python3 -m verifier.cc_admin 
        [-h] [-v] [--test_no_gpu] 
        [--driver_rim DRIVER_RIM] [--vbios_rim VBIOS_RIM]
        [--user_mode] [--nonce NONCE]
        [--rim_root_cert RIM_ROOT_CERT]
        [--rim_service_url RIM_SERVICE_URL] 
        [--ocsp_service_url OCSP_SERVICE_URL]
        [--allow_hold_cert]
        [--ocsp_nonce_enabled] 
        [--ocsp_validity_extension OCSP_VALIDITY_EXTENSION]
        [--ocsp_cert_revocation_extension_device OCSP_CERT_REVOCATION_EXTENSION_DEVICE] 
        [--ocsp_cert_revocation_extension_driver_rim OCSP_CERT_REVOCATION_EXTENSION_DRIVER_RIM]
        [--ocsp_cert_revocation_extension_vbios_rim OCSP_CERT_REVOCATION_EXTENSION_VBIOS_RIM] 
        [--ocsp_attestation_settings {default,strict}]

| Option                                                                                  | Description                                                                                                                                                                                                                                                                          |
| --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-h, --help`                                                                            | Show this help message and exit                                                                                                                                                                                                                                                      |
| `-v, --verbose`                                                                         | Print more detailed output                                                                                                                                                                                                                                                           |
| `--test_no_gpu`                                                                         | If there is no GPU and we need to test the verifier, no NVML APIs will be available, so the verifier will use hardcoded GPU info                                                                                                                                                     |
| `--driver_rim DRIVER_RIM`                                                               | The path to the driver RIM. If not provided, it will use the default file: `/usr/share/nvidia/rim/RIM_GH100PROD.swidtag`                                                                                                                                                             |
| `--vbios_rim VBIOS_RIM`                                                                 | The path to the VBIOS RIM. If not provided, it will try to find the appropriate file in `verifier_cc/samples/` directory for the VBIOS ROM flashed onto the GPU                                                                                                                      |
| `--user_mode`                                                                           | Runs the GPU attestation in user mode                                                                                                                                                                                                                                                |
| `--allow_hold_cert`                                                                     | Continue attestation if the OCSP revocation status of the certificate in the RIM files is 'certificate_hold'                                                                                                                                                                         |
| `--nonce`                                                                               | Specify a Nonce for Attestation Report                                                                                                                                                                                                                                               |
| `--rim_root_cert RIM_ROOT_CERT`                                                         | The absolute path to the root certificate to be used for verifying the certificate chain of the driver and VBIOS RIM certificate chain                                                                                                                                               |
| `--rim_service_url RIM_SERVICE_URL`                                                     | The URL to be used for fetching driver and VBIOS RIM files (e.g., `https://useast2.thim.azure.net/nvidia/v1/rim/`)                                                                                                                                                                   |
| `--ocsp_service_url OCSP_SERVICE_URL`                                                   | The URL to be used for fetching OCSP responses (e.g., `https://useast2.thim.azure.net/nvidia/ocsp/`)                                                                                                                                                                                 |
| `--ocsp_nonce_enabled`                                                                  | Enable the nonce with the provided OCSP service URL, defaults to False.                                                                                                                                                                                                              |
| `--ocsp_validity_extension OCSP_VALIDITY_EXTENSION`                                     | If the OCSP response is expired within the validity extension in hours, treat the OCSP response as valid and continue the attestation.                                                                                                                                               |
| `--ocsp_cert_revocation_extension_device OCSP_CERT_REVOCATION_EXTENSION_DEVICE`         | If the OCSP response indicates the device certificate is revoked within the extension grace period in hours, treat the certificate as good and continue the attestation.                                                                                                             |
| `--ocsp_cert_revocation_extension_driver_rim OCSP_CERT_REVOCATION_EXTENSION_DRIVER_RIM` | If the OCSP response indicates the driver RIM certificate is revoked within the extension grace period in hours, treat the certificate as good and continue the attestation.                                                                                                         |
| `--ocsp_cert_revocation_extension_vbios_rim OCSP_CERT_REVOCATION_EXTENSION_VBIOS_RIM`   | If the OCSP response indicates the VBIOS RIM certificate is revoked within the extension grace period in hours, treat the certificate as good and continue the attestation.                                                                                                          |
| `--ocsp_attestation_settings {default,strict}`                                          | The OCSP attestation settings to be used for the attestation. The default settings are to allow hold cert, validity extension, and cert revocation extension of 7 days. The strict settings are to not allow hold cert, validity extension, and cert revocation extension of 0 days. |


If you need information about any function, use
        
    help(function_name)

For example:

    e.g. help(verify_measurement_signature)


## Module details:
### rim 
The RIM (Reference Integrity Manifest) is a manifest containing golden measurements for the GPU. You can find the TCG RIM specification at the following link: [TCG RIM Specification](https://trustedcomputinggroup.org/wp-content/uploads/TCG_RIM_Model_v1p01_r0p16_pub.pdf). The RIM module performs the parsing and schema validation of the base RIM against the SWID tag schema and XML signature schema. It then performs the signature verification of the base RIM.

### attestation
The Attestation module is capable of extracting the measurements and the measurement signature. It then performs signature verification. DMTF's SPDM 1.1 MEASUREMENT response message is used as the attestation report. You can find the SPDM 1.1 specification at the following link: [SPDM 1.1 Specification](https://www.dmtf.org/sites/default/files/standards/documents/DSP0274_1.1.3.pdf).

### nvmlHandler
The nvmlHandler module utilizes the NVML API calls to retrieve GPU information, including the driver version, GPU certificates, attestation report, and more.

### verifier
The verifier module utilizes the RIM attestation module for parsing the attestation report and performing a runtime comparison of the measurements in the attestation report against the golden measurements stored in RIM.

### cc_admin
The cc_admin module retrieves the GPU information, attestation report, and the driver RIM associated with the driver version. It then proceeds with the authentication of the driver RIM and the attestation report. Afterward, it executes the verifier tool to compare the runtime measurements in the attestation report with the golden measurements stored in the driver RIM.

