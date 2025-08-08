# Confidential GPU Onboarding 

Welcome! This onboarding document walks through the process of creating an Azure Confidential VM (CVM) with an NVIDIA H100 Tensor Core GPU in Confidential Computing mode.  

Through this onboarding process, you can:
1. Deploy a secure boot enabled Azure confidential virtual machine. 
2. Attach One (1) NVIDIA H100 PCIe Tensor Core GPU in Confidential Computing mode.
3. Perform in-guest platform attestation to retrieve raw hardware evidence.
4. Perform local GPU attestation.
5. Run AI Workload in HW based Trusted Execution Environments (TEE).
6. Give us feedback and request features to help shape this VM SKU. 


## Updates
For existing customers, please note the following changes that have been made to the onboarding flow that may impact your VM configurations:

**May 6, 2025:**
For the following Nvidia drivers, there could be attestation failure. Customers need to update to driver >= r550.127.05 to mitigate. For details check the link [NVIDIA SecureAI Attestation Advisory: HBM3 Resiliency Impact on Driver Versions r550.0-r550.90.12 - NVIDIA Docs](https://docs.nvidia.com/attestation/secureai-advisory-hbm3-resiliency-impact-on-driver-versions-r550-0-r550-90-12/index.html)

- NV_GPU_DRIVER_GH100_550.54.14
- NV_GPU_DRIVER_GH100_550.54.15
- NV_GPU_DRIVER_GH100_550.90.07
- NV_GPU_DRIVER_GH100_550.90.12
- NV_GPU_DRIVER_GH100_550.113

**Dec. 4, 2024:** 
Unattended-upgrades package has been removed by default in order to avoid potential runtime service interruptions caused by unattended driver and kernel updates. 
This means that patches for security CVEs will not be automatically installed so important security updates must be checked for and installed manually. 
To learn more about this change or re-enable this package, please visit our FAQ page here: [Unattended-Upgrates](Frequently-Asked-Questions.md#q-howccan-i-re-enable-unattended-upgrades?)


## Virtual Machine Features 

- Next-generation CPUs: AMD 4th Gen EPYC processors with SEV-SNP technology to meet CPU performance for AI training/inference.
- AI state-of-the-art GPUs: NVIDIA H100 Tensor Core GPUs with 94GB of High Bandwidth Memory 3 (HBM3).
- Trusted Execution Environment (TEE) that spans confidential VM on the CPU and attached GPU, enabling secure offload of data, models, and computation to the GPU.
- VM memory encryption using hardware-generated encryption keys.
- Encrypted communication over PCIe between confidential VM and GPU.
- Attestation: Ability for CPU and GPU to generate remotely verifiable attestation reports capturing CPU and GPU security critical hardware and firmware configuration. 

## Requirements 

- [Azure subscription](https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription) and a contributor or administrator role to the subscription
- [Quota for the NCC H100 v5 VM SKU](Frequently-Asked-Questions.md#q-how-can-i-get-quota-for-creating-an-ncc-cgpu-vm)
- [Install Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)

## Instructions

The onboarding script will compelete 4 major steps that will help deploy your first Confidential GPU VM and successfully run a sample workload.

1. Environment Setup and VM Creation - creates the VM and initializes the Confidential GPU environment
2. [Optional] Key Configuration - this is only required if you choose the customer-managed key configuration (read more about key management options here: [Azure Key Management](https://learn.microsoft.com/en-us/azure/security/fundamentals/key-management))
4. Attestation and CC Mode Verification - verifies attestation and ensures the CGPU mode is enabled
5. Sample Workload Execution - provides a command to run a sample workload that can verify and complete the setup

These steps are only required the first time you are deploying your VM

Please make sure to follow all steps exactly as detailed. If you run into issues, please check the [FAQ page](Frequently-Asked-Questions.md) to check if there is more information or reach out using the contact information at the bottom of this document

## Choose your Configuration 

We support the creation of Linux Confidential GPUs using Powershell and Bash, with encryption enabled through either customer-managed keys (CMK) or platform managed keys (PMK). We recommend for first time users to try out the PMK option since it is simpler to onboard. Please select the single-step auto-onboarding script that best fits your preferred configuration: 

- [PMK flow in Powershell](docs/Confidential-GPU-H100-Onboarding-(PMK-with-Powershell).md)

- [PMK flow in Bash](docs/Confidential-GPU-H100-Onboarding-(PMK-with-Bash).md)

- [CMK flow in Powershell](docs/Confidential-GPU-H100-Onboarding-(CMK-with-Powershell).md)

- [CMK flow in Bash](docs/Confidential-GPU-H100-Onboarding-(CMK-with-Bash).md)


If you prefer to go through the steps manually, you can follow these instructions:

- [Manual Provisioning](docs/Confidential-GPU-H100-Manual-Installation-(PMK-with-Powershell).md)

- [Manual GPU Environment Setup](docs/Confidential-GPU-H100-Manual-Installation-(PMK-with-Powershell).md#upload-package)

**Preview Features**:
Provision your CGPU VM using a Community Shared Virtual Machine Image (VMI) that has the NVIDIA GPU driver, CUDA, docker, and a customized local verifier already pre-installed. This image is generated using the same single-step auto-onboarding script that is linked above so the deployed VM will yield similar results, but this method is created to help reduce manual steps and greatly reduce the setup duration.

- [VMI flow using Azure CLI](docs/Confidential-GPU-H100-VMI-Creation-CLI.md)

Please note that since this feature is in preview there is currently no SLA provided. If you have comments, feedback, or questions about the VM Image experience, please feel free to leave them in the github issues here: [az-cgpu-onboarding/Issues](https://github.com/Azure/az-cgpu-onboarding/issues/new?q=is%3Aissue).


## Availability

This offer is currently available in the East US 2, Central US, and West Europe regions. We plan to expand to more regions in a phased manner during upcoming semesters.

## Contact Information

For any questions, please check the FAQ page here: [Frequently Asked Questions](Frequently-Asked-Questions.md)

For additional help, please open a support ticket through the Azure portal. Thanks for your cooperation and help!
