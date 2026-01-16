# Confidential GPU AKS Onboarding 

Welcome! This onboarding document walks through the process of creating an Azure Kubernetes Service (AKS) cluster configured for confidential single GPU capable workloads using bash.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Helm Installation](#helm-installation)
3. [Azcli Configurations](#azcli-configurations)
4. [Create AKS Cluster with CGPU Nodepool](#create-aks-cluster-with-cgpu-nodepool)
5. [Setup Validation](#setup-validation)
6. [Driver Installation](#driver-installation)
7. [Enable Confidential GPU Mode](#enable-confidential-gpu-mode)
8. [Sample workload](#sample-workload)
9. [GPU Attestation](#gpu-attestation)
10. [Troubleshooting] (#troubleshooting)
11. [Further Information](#further-information)

## Prerequisites
Please make sure you have the following prerequisites:

 - [Azcli](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) installed        
 - [Helm](https://helm.sh/docs/intro/install/) installed - this is needed to install the NVIDIA GPU Operator, which manages GPU drivers and runtime components. Please see the Helm installation instructions below if not yet installed.

## Helm Installation
Please run the following to install helm. If you already have helm installed, skip to the [Azcli Configurations](#azcli-configurations) step.
``` bash
sudo apt-get install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
```

## Azcli Configurations
Confidential GPU features require AKS functionality that exists only in the aks-preview extension, so the following configurations must be set:

 ```bash
 # Log in to your az cli account
 az login 

 # Register the aks-preview extension
 az extension add --name aks-preview
 # Update the aks-preview extension
 az extension update --name aks-preview

 # Register the Ubuntu2404Preview feature
 az feature register --namespace Microsoft.ContainerService --name Ubuntu2404Preview
 # Check registration status
 az feature show --namespace Microsoft.ContainerService --name Ubuntu2404Preview
 # Propogate changes
 az provider register -n Microsoft.ContainerService
 ```

## Create AKS Cluster with CGPU Nodepool
Next start by provisioning a base AKS cluster. This is the control plane and system node pool. Create a new resource group if one does not exist already:
 ```bash
 rg_name="your-resource-group"
 location="eastus2"

 az group create --name $rg_name --location $location
 ```

AKS requires at least one nodepool to host system services so this provisions the initial cluster infrastructure. Please ensure the subscription you are using has quota for the SKU selected.
 ```bash
 sys_sku="standard_d8ds_v6"
 aks_name="your-aks-cluster-name"
 az aks create --resource-group $rg_name --name $aks_name --nodepool-name sysnp --node-count 1 --node-vm-size $sys_sku --os-sku Ubuntu2204 --generate-ssh-keys
 ```

Next, connect kubectl to AKS. This gives your workstation direct access to the Kubernetes API so you can deploy workloads and manage nodepools.
 ```bash
 sudo az aks install-cli
 az aks get-credentials --resource-group $rg_name --name $aks_name
 ```

Finally, add confidential H100 GPU hardware is to your cluster. Please note that Ubuntu24.04 is currently the only supported OS sku.
 ```bash
 cgpu_sku="Standard_NCC40ads_H100_v5"
 az aks nodepool add \
  --resource-group $rg_name \
  --cluster-name $aks_name \
  --name gpunp3 \
  --node-count 1 \
  --node-osdisk-size 100 \
  --os-sku Ubuntu2404 \
  --gpu-driver none \
  --node-vm-size $cgpu_sku \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3
 ```

If you want to run more `az aks nodepool` commands such as removing a node, please refer to the [Further Information](#further-information) section at the bottom of the page.

## Setup Validation
Before installing drivers, confirm that the nodepool deployed successfully to ensure your GPU nodes are registered and ready.

Check AKS nodes and extract the kernel version for later:
 ```bash
 kubectl get nodes -o wide
 # Parse out the kernel version and node name from thr GPU node
 gpu_node_name=$(kubectl get nodes -l agentpool=gpunp3 -o jsonpath='{.items[0].metadata.name}')
 kernel_version=$(kubectl get node "$gpu_node_name" -o jsonpath='{.status.nodeInfo.kernelVersion}')
 echo "$gpu_node_name"
 echo "$kernel_version"
 ```

Expected OS image and kernel version values should look like the following. Other combinations of OS image and kernel version are not yet supported.
 ```
 OS-IMAGE: Ubuntu 24.04.3 LTS
 KERNEL-VERSION: 6.8.0-1041-azure-fde
 ```

For more detailed information about the AKS nodes, run the following:
 ```bash
 # To see the details of the GPU node
 kubectl describe node $gpu_node_name

 # To see the node image
 az aks nodepool list --resource-group $rg_name --cluster-name $aks_name --query "[].{Name:name,NodeImageVersion:nodeImageVersion}" --output table
 ```

## Driver Installation
Confidential GPU nodepools do not include NVIDIA GPU drivers by default so it must be installed using the NVIDIA GPU Operator.

 ```bash
 helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
 
 # Use the extracted kernel version for the driver installation
 # Please note that this installation can take a while (up to 5 minutes).
 helm install --wait --generate-name -n gpu-operator --create-namespace nvidia/gpu-operator --version=v25.3.1 --set driver.version=580-${kernel_version}

 # Check GPU operator pods
 kubectl get pods -n gpu-operator
 ```
Checking the GPU operator pods should reveal a list containing the following:
    - gpu-operator (controller)
    - nvidia-driver-daemonset (one per GPU node)
    - nvidia-container-toolkit-daemonset
    - nvidia-device-plugin-daemonset
    - nvidia-dcgm / dcgm-exporter
    - gpu-feature-discovery (GPU feature discovery)

Once it shows that the `driver-daemonset` pod is running, the driver has been installed! Verify this by checking the logs in the daemonset pod:
 ```bash
 # Find the driver-daemonset pod and check driver installation logs
 dm_pod=$(kubectl get pods -n gpu-operator | grep driver-daemonset | awk '{print $1}')
 kubectl logs -n gpu-operator $dm_pod
 ```

## Enable Confidential GPU Mode
Once the driver has been successfully installed, Confidential GPU mode must be enabled. This is a key security requirement for protecting data-in-use and enabling attested GPU execution.
 ```bash
 kubectl exec $dm_pod -n gpu-operator -- nvidia-smi
 kubectl exec $dm_pod -n gpu-operator -- nvidia-smi conf-compute -f
 kubectl exec $dm_pod -n gpu-operator -- nvidia-smi conf-compute -srs 1
 kubectl exec $dm_pod -n gpu-operator -- nvidia-smi conf-compute -q
 ```

Once the confidential mode has been enabled, check the kubectl pods and wait for the `nvidia-cuda-validator-xxx` pod to show `Completed` state. The `nvidia-operator-validator-xxx` pod should show it is in `Running` state.
 ```bash
 kubectl get pods -n gpu-operator
 ```

## Sample workload
Congratulations! At this point your AKS cluster is successfully set up with ACC node(s) that have NVIDIA drivers installed. Optionally, follow the steps below to run a sample workload and see the CGPU at work!

Download the following yaml file: [samples-tf-matmul-demo.yaml](samples-tf-matmul-demo.yaml)

Run the workload: 
 ```bash
 kubectl apply -f samples-tf-matmul-demo.yaml
 ```

List the job pods, find something starting with to tf-matmul-demo-xxxx, and wait until it is completed:
 ```bash
 kubectl get pods
 ```

Once the `tf-matmul-demo-xxxx` pod is completed, view the job logs:
 ```bash
 kubectl logs tf-matmul-demo-xxxx
 ```

## GPU Attestation
Once your confidential GPU setup is complete, you can use a new pod that downloads the latest GPU verifier from our Github release package to demonstrate that the GPU attestation is working properly.

First download the following yaml file: [cgpu-aks-attestation.yaml](cgpu-aks-attestation.yaml).

Then you can apply the configuration file to your cluster:
 ```bash
 kubectl apply -f cgpu-aks-attestation.yaml
 ```

Check the attestation job status:
 ```bash
 kubectl get pods -n attest -l job-name=local-gpu-attestation
 ```

Expected output should show a pod in `Completed` status:
 ```
 NAME                          READY   STATUS      RESTARTS   AGE
 local-gpu-attestation-xxxxx   0/1     Completed   0          2m15s
 ```

View the attestation results:
 ```bash
 # Replace the pod name with your actual pod name from the previous command
 kubectl logs -n attest local-gpu-attestation-xxxxx
 ```

The logs should show the GPU attestation process and results, confirming that your confidential GPU setup is working correctly.

## Troubleshooting
If you run into any error while GPU operator pods are initializing (ex: the nvidia-driver-daemonset is showing a status of "CrashLoopBackOff"), try deleting the node and restarting the steps starting at [Setup Validation](#setup-validation):
```bash
 helm delete -n gpu-operator $(helm list -n gpu-operator | grep gpu-operator | awk '{print $1}')
```

## Further Information
For more details on az aks nodepool commands, please refer to the following documentation: [Az AKS Nodepool Commands](https://learn.microsoft.com/en-us/cli/azure/aks/nodepool?view=azure-cli-latest)
