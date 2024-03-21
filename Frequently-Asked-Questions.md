## Frequently Asked Questions

Q: Why is the kernel version locked?
A: Kernel version 6.2.0.1018 is the only working kernel with driver version 535.129.03. The latest Nvidia driver signed by Canonical does not have a signed RIM (Reference Integrity Manifest), which would case the GPU attestation to fail.

Q: Why does the `dmesg` not display `AMD SEV-SNP`?
A: This does not mean SEV-SNP is not enabled, this is just a characteristic of CVMs which don't provide this interface. The firmware-generated SNP report is stored elsewhere.
