# Table of Contents
1. [Dev Tools Overview](https://github.com/Azure/az-cgpu-onboarding/blob/main/src/dev_tools/README.md#dev-tools-overview)

2. [Instructions for Contributions](https://github.com/Azure/az-cgpu-onboarding/blob/main/src/dev_tools/README.md#instructions-for-contributions)

## Dev Tools Overview

The following scripts were created to help automate the process of creating and testing
drop packages:

`init.ps1` -> makes sure your environment is set up with the az module installed and logs into your Azure account

`build.ps1` -> will generate the 3 packages into a 'drops' folder: cgpu-onboarding-package.tar.gz, 
cgpu-h100-auto-onboarding-windows.zip, and cgpu-h100-auto-onboarding-linux.tar.gz

## Instructions for Contributions

In order to maintain stability and ensure quality of our releases, we have established the following workflow:
1. Development work is done on the universal `dev` branch
2. Once all changes for the next iteration are ready, they will go into the official release branch. Release branches are named in this format: V2.1.0. If it is a new release version, the corresponding release package has to be created and be labeled as a 'pre-release'
3. Our scheduled testing will automatically pick up the latest pre-release and run validation tests to ensure the package is working
4. Once all validations are passed from step 3, the release branch can get merged into the main branch.
