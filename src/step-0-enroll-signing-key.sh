openssl x509 -in linux_kernel_apm_sha256_cert.pem -inform PEM -out linux_kernel_apm_sha256_cert.der -outform DER
sudo mokutil --import linux_kernel_apm_sha256_cert.der