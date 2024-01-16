# Confidential GPU Private Preview Onboarding 

The following four major steps are provided to help deploy your first Confidential GPU VM and to run a sample workload. The first step sets up the Confidential GPU environment and create the VM. The second step is optional, only required if you choose the customer managed key option (read more about key management options here: [Azure Key Management](https://learn.microsoft.com/en-us/azure/security/fundamentals/key-management)). The third step performs attestation verification and ensures the CGPU mode has been turned on successfully. The last step helps run a sample workload to verify and complete the setup. These steps are only required the first time you are deploying your VM.

1. Create CGPU VM
2. [Optional] Create Customer Managed Key
4. Attestation Verification
5. Workload Running

Please make sure to follow all steps exactly as detailed. If you run into issues, please reach out using the contact information at the bottom of this document

## Choose your Configuration 

We support the options to create confidential GPUs with Windows and Linux hosts, as well as with customer (CMK) and platform (PMK) managed keys:

- [Onboarding Docs (Windows host with PMK)](Confidential-GPU-H100-Onboarding-(PMK-for-Windows).md)

- [Onboarding Docs (Windows host with CMK)](Confidential-GPU-H100-Onboarding-(CMK-for-Windows).md)

- [Onboarding Docs (Linux host with PMK)](Confidential-GPU-H100-Onboarding-(PMK-for-Linux).md)

- [Onboarding Docs (Linux host with CMK)](Confidential-GPU-H100-Onboarding-(CMK-for-Linux).md)

## Contact Information
Confidential GPU Preview: cgpupreview@microsoft.com
