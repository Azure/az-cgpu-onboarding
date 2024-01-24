# Confidential GPU Private Preview Onboarding 

Welcome to this preview! This onboarding document helps to create an Azure confidential VM with NVIDIA H100 Tensor Core GPU in Confidential Computing mode.  

Please note that any associated materials or documentation below are strictly confidential and subject to obligations in the Non-Disclosure Agreement (NDA) signed between Microsoft and your organization. 

In this preview, you can:
1. Deploy a secure boot enabled Azure confidential virtual machine. 
2. Attach One (1) NVIDIA H100 PCIe Tensor Core GPU in Confidential Computing mode.
3. Perform in-guest platform attestation to retrieve raw hardware evidence.
4. Perform local GPU attestation.
5. Run AI Workload in HW based Trusted Execution Environments (TEE).
6. Give us feedback and request features to help shape this VM SKU. 

## Virtual Machine Features 

- Next-generation CPUs: AMD 4th Gen EPYC processors with SEV-SNP technology to meet CPU performance for AI training/inference.
- AI state-of-the-art GPUs: NVIDIA H100 Tensor Core GPUs with 94GB of High Bandwidth Memory 3 (HBM3).
- Trusted Execution Environment (TEE) that spans confidential VM on the CPU and attached GPU, enabling secure offload of data, models, and computation to the GPU.
- VM memory encryption using hardware-generated encryption keys.
- Encrypted communication over PCIe between confidential VM and GPU.
- Attestation: Ability for CPU and GPU to generate remotely verifiable attestation reports capturing CPU and GPU security critical hardware and firmware configuration. 

## Requirements 

- [Azure subscription](https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription) and a contributor or administrator role to the subscription
- Quota for the NCC H100 v5 VM SKU
- [Install Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)

## Instructions

The following four major steps are provided to help deploy your first Confidential GPU VM and to run a sample workload. The first step sets up the Confidential GPU environment and create the VM. The second step is optional, only required if you choose the customer managed key option (read more about key management options here: [Azure Key Management](https://learn.microsoft.com/en-us/azure/security/fundamentals/key-management)). The third step performs attestation verification and ensures the CGPU mode has been turned on successfully. The last step helps run a sample workload to verify and complete the setup. These steps are only required the first time you are deploying your VM.

1. Create CGPU VM
2. [Optional] Create Customer Managed Key
4. Attestation Verification
5. Workload Running

Please make sure to follow all steps exactly as detailed. If you run into issues, please reach out using the contact information at the bottom of this document

## Choose your Configuration 

We support the options to create confidential GPUs with Windows and Linux hosts, as well as with customer (CMK) and platform (PMK) managed keys. We recommend for first time users to try out the PMK option since it's simpler to onboard.

- [Onboarding Docs (Windows host with PMK)](Confidential-GPU-H100-Onboarding-(PMK-for-Windows).md)

- [Onboarding Docs (Linux host with PMK)](Confidential-GPU-H100-Onboarding-(PMK-for-Linux).md)

- [Onboarding Docs (Windows host with CMK)](Confidential-GPU-H100-Onboarding-(CMK-for-Windows).md)

- [Onboarding Docs (Linux host with CMK)](Confidential-GPU-H100-Onboarding-(CMK-for-Linux).md)

## Future Capabilities  

- Official support for Azure Portal and Native Azure CLI
- Support for NVIDIA H100 PCIe driver in Linux Kernel
- NVIDIA certified VMI-based provisioning with the GPU driver, CUDA, ML tools, and a customized local verifier already pre-installed
- In-guest attestation evidence appraised by Microsoft Azure Attestation Service (MAA)

## Availability and Reliability Expectations 

This preview is currently availability in the East US 2 region. We plan to expand to more regions in a phased manner during public preview/General Availability (GA).  Non-production data is recommended during this phase of the preview. We are not providing a reliability SLA during the preview phase. 

## Contact Information

Support will be directly with the product team via the email Confidential GPU Preview: cgpupreview@microsoft.com   
The service will be taken down around 1-2 times per month for security and performance updates.
Thanks for your cooperation and help!
