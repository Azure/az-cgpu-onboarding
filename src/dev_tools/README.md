# Table of Contents
1. [Dev Tools Overview](https://github.com/Azure/az-cgpu-onboarding/blob/main/src/dev_tools/README.md#dev-tools-overview)

2. [Instructions for Contributions](https://github.com/Azure/az-cgpu-onboarding/blob/main/src/dev_tools/README.md#instructions-for-contributions)

## Dev Tools Overview

The following scripts were created to help automate the process of creating and testing drop packages:

`init.ps1` -> makes sure your environment is set up with the az module installed and logs into your Azure account

`build.ps1` -> will generate the 3 packages into a 'drops' folder: cgpu-onboarding-package.tar.gz, 
cgpu-h100-auto-onboarding-windows.zip, and cgpu-h100-auto-onboarding-linux.tar.gz

`utility_update_version.ps1` -> replaces all ocurrences of the old version number with the updated one from `src\version.txt`. Versions should have the following format: V2.1.0 - uppercase V followed by 3 sets of integers. If this condition is not met in either the new or the old version, an error message will be printed.

## Instructions for Contributions

In order to maintain stability and ensure quality of our releases, we have established the following workflow:
1. Development work is done on individual branches
2. Once all changes are ready, they are merged into the 'main' branch. The 'main' branch here functions as the 'dev' branch for the public [az-cgpu-onboarding](https://github.com/Azure/az-cgpu-onboarding) repository used by customers.
3. Pipelines will pick up the changes and pull them into the automation testing where we can validate changes.
4. Once all validations are passed from step 3, the updates will be cloned over to the public repository.