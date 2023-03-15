# Dev Tools Instructions

The following scripts were created to help automate the process of creating and testing
drop packages:

`init.ps1` -> logs in to your Azure account to download the driver and verifier from an Azure storage container
into a local 'packages' folder

`build.ps1` -> will generate the 3 packages into a 'drops' folder: cgpu-onboarding-package.tar.gz, 
cgpu-sb-enable-vmi-onboarding.zip, and cgpu-sb-enable-vmi-onboarding.tar.gz