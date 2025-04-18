# Frequently Asked Questions

Below are a list of frequently asked questions and answers.

## Q: How can I get quota for creating an NCC CGPU VM?

A: Details for the specific process to be granted quota for an NCC CGPU VM can be found on the [CGPU Quota](docs/CGPU-Quota.md) page.


## Q: How can I capture an image of my CGPU VM and share it?

A: There are separate instructions for creating and sharing virtual machine images (VMIs) for within-subscription and across-subscription use cases. Please refer to the document that is applicable to your situation: 

1. [Internal VMI Creation And Sharing Instructions](docs/Internal-VMI-Creation-And-Sharing-Instructions.md): used within the same subscription
2. [External VMI Creation And Sharing Instructions](docs/External-VMI-Creation-And-Sharing-Instructions.md): used between different subscriptions


## Q: How can I check my driver version and update it?

A: First please make sure all your currently running workloads are saved and termated, then run the following commands to check your driver version and then update it:
```
# check the version
nvidia-smi

# run the updates
sudo apt update
sudo apt upgrade
```

After running this, the VM has to be rebooted before running attestation or launching any workloads. Alternatively, please refer to the [Driver Failure Mitigation](docs/Driver-Failure-Mitigation.md) page that has detailed instructions on how to fully uninstall and reinstall the driver.


## Q: My CGPU driver stopped working after an unattended update, how can I fix it?

A: There is an NVIDIA driver/library version mismatch which can cause a failure if you are running certain NVIDIA driver versions when your machine runs an unattended upgrade. Possible error messages you may see if this is the case are: 

`Failed to initialize NVML: Driver/Library version mismatch` or 

`NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver. Make sure that the latest NVIDIA driver is installed and running.`

If this is the case for you, please refer to the following page for more detailed mitigation instructions: [Driver Failure Mitigation](docs/Driver-Failure-Mitigation.md)


## Q: How can I re-enable Unattended-Upgrades?

A: By default, Unattended-Upgrades is disabled through our onboarding script. Unattended-Upgrades is a package for Ubuntu that allows the automatic installation of security updates. This means that critical updates are installed without user intervention, but these installations can cause potential runtime service interruptions to currently running workloads and attestation.

If you would like to re-enable unattended upgrades on your VM, please run:
```
sudo apt install unattended-upgrades
```


## Q: How can I use OpenSSL `(>=3.1.0)` for Confidential H100 GPU bandwidth improvement?

OpenSSL version 3.1.0 and above are known to significantly improve the bandwidth between H100 Confidential GPU and CPU, thanks to the encryption performance boost provided by AVX512.

We have created a script to build and install OpenSSL 3.4.1 to `/opt/openssl` where you have the option to specify the `LD_LIBRARY_PATH` to `/opt/openssl/lib64`. Note that the system's OpenSSL 3.0.2 remains untouched and continues to be the default version.

Run the following command to install it: 
```
sudo bash utilities-install-openssl.sh
```
For more specifics on H100 GPU bandwidth using the different versions of SSL, refer to the [OpenSSL-Details](docs/OpenSSL-Details.md) page.


## Q: How can I deploy my CGPU VM manually if I don't want to run the auto-onboarding scripts?

A: We have detailed out the options to deploy a CGPU VM manually [here](docs/Confidential-GPU-H100-Manual-Installation-(PMK-for-Windows).md). It also contains the following steps needed to fully set up the CGPU environment in order to run a sample workload.


## Q: Why does the `dmesg` not display `AMD SEV-SNP`?

A: This is the intended behavior because the AMD SEV-SNP offering on Azure runs in the vTOM (virtual Top of Memory) mode and the SEV-SNP CPUID capability is not exposed to the VM, though SEV-SNP is in use. In such a CVM, the native attestation interface /dev/sev-guest is unsupported; instead, the VM should perform attestation via vTPM.
To detect such an AMD SEV-SNP VM on Azure, a user should check the CPU leaves below :
CPUID leaf 0x40000003’s EBX.bit22 is 1 AND
CPUD leaf 0x4000000C’s EAX.bit0 is 1, and EBX.bit 0~3 is 2.
(refer to https://elixir.bootlin.com/linux/latest/source/arch/x86/kernel/cpu/mshyperv.c#L445)

NVIDIA is working on implementing SEV-SNP checks for Hyper-V and are planning on will releasing it with the TRD5 release in September 2024.


## Q: How can I check my CGPU VM's HyperV SEV-SNP status is enabled?

A: Use the following command to check the HyperV SEV-SNP enablement on your machine: 
```
sudo apt-get update
sudo apt install cpuid
cpuid -l 0x4000000C -1 | awk '$4 ~ /^ebx=.*2$/ { print "AMD SEV-SNP is enabled"}'
```

For more detailed information on how to perform guest attestation for Azure SEV-SNP CVM, please refer to the following page: [SNP Guest Attestation](docs/SNP-Guest-Attestation-Verification.md)


## Q: Can I get NVMe support for my CGPU VM?

A: NVMe support is currently not supported for CGPU VMs, but this feature is being worked on for future releases. There are bugs that show NVMe attachment support when creating CGPU VMs from the Azure portal which we are working to resolve.


## Q: My question is not listed above, where can I find the answer?
If you are using an older release version and your question is not listed below, please try checking the [Legacy FAQ](docs/Legacy-FAQ.md) page.
