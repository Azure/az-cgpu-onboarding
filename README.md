# Confidential GPU Onboarding 

Welcome! This onboarding document helps to create an Azure Confidential VM (CVM) with NVIDIA H100 Tensor Core GPU in Confidential Computing mode.  

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

The following four major steps are provided to help deploy your first Confidential GPU VM and to run a sample workload. The first step sets up the Confidential GPU environment and create the VM. The second step is optional, only required if you choose the customer managed key option (read more about key management options here: [Azure Key Management](https://learn.microsoft.com/en-us/azure/security/fundamentals/key-management)). The third step performs attestation verification and ensures the CGPU mode has been turned on successfully. The last step helps run a sample workload to verify and complete the setup. These steps are only required the first time you are deploying your VM.

1. Create CGPU VM
2. [Optional] Create Customer Managed Key
4. Attestation Verification
5. Workload Running

Please make sure to follow all steps exactly as detailed. If you run into issues, please check the [FAQ page](Frequently-Asked-Questions.md) to check if there is more information or reach out using the contact information at the bottom of this document

## Choose your Configuration 

We support the options to create confidential GPUs with Windows and Linux hosts, as well as with customer (CMK) and platform (PMK) managed keys. We recommend for first time users to try out the PMK option since it's simpler to onboard. You can chose between the following instruction options depending on your preferred configuration. We have created an easy to use one-step auto-onboarding script for bash and powershell users:

- [PMK flow in Powershell](docs/Confidential-GPU-H100-Onboarding-(PMK-with-Powershell).md)

- [PMK flow in Bash](docs/Confidential-GPU-H100-Onboarding-(PMK-with-Bash).md)

- [CMK flow in Powershell](docs/Confidential-GPU-H100-Onboarding-(CMK-with-Powershell).md)

- [CMK flow in Bash](docs/Confidential-GPU-H100-Onboarding-(CMK-with-Bash).md)


If you prefer to go through the steps manually, you can follow these instructions:

- [Manual Provisioning](docs/Confidential-GPU-H100-Manual-Installation-(PMK-with-Powershell).md)

- [Manual GPU Environment Setup](docs/Confidential-GPU-H100-Manual-Installation-(PMK-with-Powershell).md#upload-package)

## Future Capabilities  

- NVIDIA certified VMI-based provisioning with the GPU driver, CUDA, ML tools, and a customized local verifier already pre-installed
- In-guest attestation evidence appraised by Microsoft Azure Attestation Service (MAA)

## Availability

This offer is currently available in the East US 2 and West Europe regions. We plan to expand to more regions in a phased manner during upcoming semesters.

## Contact Information

For any questions, please check the FAQ page here: [Frequently Asked Questions](Frequently-Asked-Questions.md)

For additional help, please open a support ticket through the Azure portal. Thanks for your cooperation and help!
