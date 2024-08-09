#!/bin/bash

##- Open cmk module
##```
##cd <Repo Path>/src/cmk_module
##```
##
##- Call bash script
##```
##bash Linux/cgpu-deploy-cmk-des.sh \
##-s "<subscriptionId>" \
##-t "<tenantId>" \
##-r "eastus2" \
##-g "cmk-$(date +"%Y%m%d%H%M%S")-rg" \
##-k "cmk-$(date +"%Y%m%d%H%M%S")-key" \
##-v "cmk-$(date +"%Y%m%d%H%M%S")-kv" \
##-p "skr-policy.json" \
##-d "cmk-$(date +"%Y%m%d%H%M%S")-desdeploy" \
##-n "cmk-$(date +"%Y%m%d%H%M%S")-des" \
##-m "deployDES.json"
##```


# Initialize variables
subscriptionId=""
tenantId=""
region="eastus2"
resourceGroup=""
keyName=""
keyVault=""
policyPath=""
desName=""
deployName=""
desArmTemplate=""
keySize=3072
cvmAgentId="bf7b6499-ff71-4aa2-97a4-f372087be7f0"

# Set MgServicePrincipal
SET-SERVICEPRINCIPAL() {

   # Update the list of packages
   sudo apt-get update

   sudo apt-get install -y jq

   # TODO Add check for service principal
   servicePrincipalExists=$(az ad sp list --filter "appId eq '$cvmAgentId'" | jq -r '.[].appId')
   if [ "$servicePrincipalExists" == "$cvmAgentId" ]; then
      echo "---------------------------------- Service principal [$cvmAgentId] already exists ----------------------------------"
      
   else
      echo "---------------------------------- Creating service principal [$cvmAgentId] ----------------------------------"
      
      # Install pre-requisite packages
      sudo apt-get install -y wget apt-transport-https software-properties-common

      # Download the Microsoft repository GPG keys
      wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"

      # Register the Microsoft repository GPG keys
      sudo dpkg -i packages-microsoft-prod.deb

      # Enable the "universe" repositories
      sudo add-apt-repository universe

      # Install PowerShell
      sudo apt-get install -y powershell

      #- (Prerequisite) Set MgServicePrincipal
      # Install Microsoft.Graph PowerShell module
      sudo pwsh -Command "Install-Module Microsoft.Graph -Scope CurrentUser -Repository PSGallery"
      sudo pwsh -Command "Get-Module -Name Microsoft.Graph -ListAvailable"

      # Create MgServicePrincipal
      sudo pwsh -Command "Connect-Graph -Tenant '$tenantId' -Scopes Application.ReadWrite.All; New-MgServicePrincipal -AppId '$cvmAgentId' -DisplayName 'Confidential VM Orchestrator'"

      # Wait for service principal to be created
      for i in {1..10}; do
         servicePrincipalExists=$(az ad sp list --filter "appId eq '$cvmAgentId'" | jq -r '.[].appId')
         if [ "$servicePrincipalExists" == "$cvmAgentId" ]; then
            break
         fi
         echo "---------------------------------- Waiting for service principal [$cvmAgentId] to be created ----------------------------------"
         sleep 5
      done

      echo "---------------------------------- Service principal [$cvmAgentId] created ----------------------------------"
   fi


}

# Deploy CMK DES
DEPLOY-CMK-DES() {

   # Parse parameter options
   while getopts ":s:t:r:g:k:v:p:d:n:m:" opt; do
      case $opt in
         s) subscriptionId=$OPTARG;;
         t) tenantId=$OPTARG;;
         r) region=$OPTARG;;
         g) resourceGroup=$OPTARG;;
         k) keyName=$OPTARG;;
         v) keyVault=$OPTARG;;
         p) policyPath=$OPTARG;;
         d) deployName=$OPTARG;;
         n) desName=$OPTARG;;
         m) desArmTemplate=$OPTARG;;
         \?) echo "Invalid option -$OPTARG" >&2
               return 1
         ;;
      esac
   done

   echo "Parameters:"
   echo "Subscription ID: $subscriptionId"
   echo "Tenant ID: $tenantId"
   echo "Region: $region"
   echo "Resource Group: $resourceGroup"
   echo "Key Name: $keyName"
   echo "Key Vault: $keyVault"
   echo "Policy Path: $policyPath"
   echo "DES Name: $desName"
   echo "Deploy Name: $deployName"
   echo "DES ARM Template: $desArmTemplate"

   # Login to Azure
   az account clear
   az login --tenant $tenantId > /dev/null
   az account set --subscription $subscriptionId
   echo "---------------------------------- Login to [$subscriptionId] ----------------------------------"

   # Set MgServicePrincipal
   SET-SERVICEPRINCIPAL

   # Check if the resource group exists
   groupExists=$(az group exists --name $resourceGroup)
   groupExists=$(echo "$groupExists" | tr -cd '[:alnum:]')
   if [ "$groupExists" == "false" ]; then
      # Create the resource group since it does not exist
      az group create --name $resourceGroup --location $region
      echo "---------------------------------- Resource group [$resourceGroup] created ----------------------------------"
   else
      echo "---------------------------------- Resource group [$resourceGroup] already exists ----------------------------------"
   fi

   az keyvault create --name $keyVault --resource-group $resourceGroup --location $region --sku Premium --enable-purge-protection --enable-rbac-authorization false
   echo "---------------------------------- KeyVault [$keyVault] created ----------------------------------"

   cvmAgent=$(az ad sp show --id $cvmAgentId | jq -r '.id')
   az keyvault set-policy --name $keyVault --resource-group $resourceGroup --object-id $cvmAgent --key-permissions get release
   az keyvault key create --vault-name $keyVault --name $keyName --ops wrapKey unwrapkey --kty RSA-HSM --size $keySize --exportable true --policy $policyPath
   echo "---------------------------------- KeyName [$keyName] created ----------------------------------"

   encryptionKeyVaultId=$(az keyvault show -n $keyVault -g $resourceGroup --query "id" -o tsv)
   encryptionKeyVaultId=$(echo "$encryptionKeyVaultId" | tr -cd '[:alnum:]-/,.:')
   echo "---------------------------------- encryptionKeyVaultId [$encryptionKeyVaultId]----------------------------------"

   encryptionKeyURL=$(az keyvault key show --vault-name $keyVault --name $keyName --query "key.kid" -o tsv)
   encryptionKeyURL=$(echo "$encryptionKeyURL" | tr -cd '[:alnum:]-/,.:')  
   echo "---------------------------------- encryptionKeyURL [$encryptionKeyURL]----------------------------------"

   az deployment group create \
      -g $resourceGroup \
      -n $deployName \
      -f $desArmTemplate \
      -p desName=$desName \
      -p encryptionKeyURL=$encryptionKeyURL \
      -p encryptionKeyVaultId=$encryptionKeyVaultId \
      -p region=$region
   echo "---------------------------------- Des deployment [$desName] created----------------------------------"

   desIdentity=$(az disk-encryption-set show -n $desName -g $resourceGroup --query "identity.principalId" -o tsv)
   desIdentity=$(echo "$desIdentity" | tr -cd '[:alnum:]-/,.:')
   echo "---------------------------------- desIdentity [$desIdentity] retrieved ----------------------------------"

   az keyvault set-policy -n $keyVault \
      -g $resourceGroup \
      --object-id $desIdentity \
      --key-permissions wrapkey unwrapkey get
   echo "---------------------------------- Set policy ----------------------------------"

   desID=$(az disk-encryption-set show -n $desName -g $resourceGroup --query [id] -o tsv)
   desID=$(echo "$desID" | tr -cd '[:alnum:]-/,.:')
   echo "---------------------------------- [$desID] is the desID ----------------------------------"

}

# call DEPLOY-CMK-DES and pass all the arguments
DEPLOY-CMK-DES "$@" 2>&1 
