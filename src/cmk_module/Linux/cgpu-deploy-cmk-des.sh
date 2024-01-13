#!/bin/bash

#- (Prerequisite) Set MgServicePrincipal
# You will need this step if you have not set your cvmAgentId for your tenant
# bash Linux/pre-requisite.sh

## Sample Command:
## bash Linux/cgpu-deploy-cmk-des.sh \
## -s "85c61f94-8912-4e82-900e-6ab44de9bdf8" \
## -r "eastus2" \
## -g "cmk-$(date +"%H%M%S")-rg" \
## -k "cmk-$(date +"%H%M%S")-key" \
## -v "cmk-$(date +"%H%M%S")-kv" \
## -p "skr-policy.json" \
## -d "cmk-$(date +"%H%M%S")-desdeploy" \
## -n "cmk-$(date +"%H%M%S")-des" \
## -t "deployDES.json"

# Deploy CMK DES
DEPLOY-CMK-DES() {

   # Initialize variables
   local subscriptionId=""
   local region="eastus2"
   local resourceGroup=""
   local keyName=""
   local keyVault=""
   local policyPath=""
   local desName=""
   local deployName=""
   local desArmTemplate=""
   local keySize=3072
   local cvmAgentId="bf7b6499-ff71-4aa2-97a4-f372087be7f0"

   # Parse options
   while getopts ":s:r:g:k:v:p:d:n:t:" opt; do
      case $opt in
         s) subscriptionId=$OPTARG;;
         r) region=$OPTARG;;
         g) resourceGroup=$OPTARG;;
         k) keyName=$OPTARG;;
         v) keyVault=$OPTARG;;
         p) policyPath=$OPTARG;;
         d) deployName=$OPTARG;;
         n) desName=$OPTARG;;
         t) desArmTemplate=$OPTARG;;
         \?) echo "Invalid option -$OPTARG" >&2
               return 1
         ;;
      esac
   done

   echo "Parameters:"
   echo "Subscription ID: $subscriptionId"
   echo "Region: $region"
   echo "Resource Group: $resourceGroup"
   echo "Key Name: $keyName"
   echo "Key Vault: $keyVault"
   echo "Policy Path: $policyPath"
   echo "DES Name: $desName"
   echo "Deploy Name: $deployName"
   echo "DES ARM Template: $desArmTemplate"
   az login
   az account set --subscription $subscriptionId
   echo "---------------------------------- Login to [$subscriptionId] ----------------------------------"

   groupExists=$(az group exists --name $resourceGroup)
   groupExists=$(echo "$groupExists" | tr -cd '[:alnum:]')
   if [ "$groupExists" == "false" ]; then
      # Create the resource group since it does not exist
      az group create --name $resourceGroup --location $region
      echo "---------------------------------- Resource group [$resourceGroup] created ----------------------------------"
   else
      echo "---------------------------------- Resource group [$resourceGroup] already exists ----------------------------------"
   fi

   az keyvault create --name $keyVault --resource-group $resourceGroup --location $region --sku Premium --enable-purge-protection
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
