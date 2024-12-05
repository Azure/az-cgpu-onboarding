# Attention Azure Confidential GPU VM Users

### Impact Statement
We have identified an issue in which the driver failes to communicate with the NVIDIA GPU due to unattended updates that lead to a library/driver version mismatch. Potential error messages that can be seen if this issue is present are: `Failed to initialize NVML: Driver/Library version mismatch` or `NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver. Make sure that the latest NVIDIA driver is installed and running.`

### Recommended Action
In order to resolve this issue, we recommend customers execute the following commands:

First purge the NVIDIA driver from your VM. Reinstallation of the driver and/or kernel signature are not sufficient for this step and will cause the driver to fail to load:
```
sudo apt remove -y --purge *nvidia*550*
```

Once purged, run the update kernel script from the onboarding package to ensure the kernel version is up-to-date. This may reboot your machine if an update is made:
```
cd ~/cgpu-onboarding-package; sudo bash step-0-prepare-kernel.sh
```

Then fully reinstall the driver and signature through the onboarding script that came in your package. This will set up Linux configuration files and reinstall the driver and its signature:
```
cd ~/cgpu-onboarding-package; sudo bash step-1-install-gpu-driver.sh
```

You can double-check that the update was successful by running the following commands:
```
# output the new kernel version:
uname -r

# check the GPU connection
nvidia-smi
```

You should see that nvidia-smi is working without having to reboot your machine.
