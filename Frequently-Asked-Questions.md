# Frequently Asked Questions

Below are a list of frequently asked questions and answers. If you are using an older release version and your question is not listed below, please try checking the [Legacy FAQ](https://github.com/Azure/az-cgpu-onboarding/blob/main/Legacy-FAQ.md) page.


## Q: How can I capture an image of my VM and share it?

A: Please refer to this page that contains detailed information on different VMI scenarios and which options are supported: [VMI Sharing Instructions](https://github.com/Azure/az-cgpu-onboarding/blob/main/Frequently-Asked-Questions.md)


## Q: How can I use OpenSSL `(>=3.1.0)` for Confidential H100 GPU bandwidth improvement?

OpenSSL version 3.1.0 and above are known to significantly improve the bandwidth between H100 Confidential GPU and CPU, thanks to the encryption performance boost provided by AVX512.

We have created a script to build and install OpenSSL 3.3.1 to `/opt/openssl` where you have the option to specify the `LD_LIBRARY_PATH` to `/opt/openssl/lib64`. Note that the system's OpenSSL 3.0.2 remains untouched and continues to be the default version.

Run the following command to install it: 
```
sudo bash utilities-install-openssl.sh
```
For more specifics on H100 GPU bandwidth using the different versions of SSL, refer to the [OpenSSL-Details](https://github.com/Azure/az-cgpu-onboarding/blob/main/OpenSSL-Details.md) page.


## Q: How can I deploy my CGPU VM manually if I don't want to run the auto-onboarding scripts?

A: We have detailed out the options to deploy a CGPU VM manually [here](https://github.com/Azure/az-cgpu-onboarding/blob/main/Confidential-GPU-H100-Manual-Installation-(PMK-for-Windows).md). It also contains the following steps needed to fully set up the CGPU environment in order to run a sample workload.


## Q: Why does the `dmesg` not display `AMD SEV-SNP`?

A: This does not mean SEV-SNP is not enabled, this is just a characteristic of CVMs which don't provide this interface. The firmware-generated SNP report is stored elsewhere.