# Dev Tools Instructions

The following scripts were created to help automate the process of creating and testing
drop packages.

`init.ps1` -> logs in to your Azure account to download the driver and verifier from Azure storage container
`build.ps1` -> will generate the 3 drop packages: cgpu-onboarding-package.tar.gz, cgpu-sb-enable-