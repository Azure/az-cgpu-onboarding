## This module helps generate .der file from nvidia provided .pem file, and enroll into the sysntem.
##
## Requirements: 
##		nvdia singing key:		linux_kernel_apm_sha256_cert.pem
##
## Example: 
##      bash step-0-enroll-signing-key.sh 
##

openssl x509 -in linux_kernel_apm_sha256_cert.pem -inform PEM -out linux_kernel_apm_sha256_cert.der -outform DER
sudo mokutil --import linux_kernel_apm_sha256_cert.der