#!/bin/bash

subscriptionId=$1
region=$2
resourceGroup=$3
keyVault=$4
policyPath=$5
desName=$6
deployName=${7}
desArmTemplate=${8}

cvmAgentId="bf7b6499-ff71-4aa2-97a4-f372087be7f0"
keyName="$timeString-CMK-key"
keySize=3072

az login
az account set --subscription $subscriptionId
echo "---------------------------------- Login to [$subscriptionId] ----------------------------------"

az group create --name $resourceGroup --location $region
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

