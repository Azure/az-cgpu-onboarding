#!/bin/bash
  ###Sample Parameters:
  #timeString=$(date +"%H%M%S")
  #subscriptionId = "85c61f94-8912-4e82-900e-6ab44de9bdf8"
  #region = "eastus2"
  #resourceGroup ="$timeString-CMK-rg"
  #keyName = "$timeString-CMK-key"
  #keyVault = "$timeString-CMK-kv"
  #policyPath = "skr-policy-2.json"
  #desName = "$timeString-CMK-des"
  #deployName = "$timeString-CMK-desdeploy"
  #desArmTemplate = "deployDES.json"
#
  ###Sample Command:
  #bash Linux/cgpu-deploy-cmk-des.sh \
  #--subscriptionId $subscriptionId \
  #--region $region \
  #--resourceGroup $resourceGroup \
  #--keyName $keyName \
  #--keyVault $keyVault \
  #--policyPath $policyPath \
  #--desName $desName \
  #--deployName $deployName \
  #--desArmTemplate $desArmTemplate

cvmAgentId="bf7b6499-ff71-4aa2-97a4-f372087be7f0"
keySize=3072
$region="eastus2"

while getopts ":-" opt; do
   case "$opt" in
      -)
         case "${OPTARG}" in
            subscriptionId)
               subscriptionId="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
               ;;
            region)
               region="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
               ;;
            resourceGroup)
               resourceGroup="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
               ;;
            keyVault)
               keyVault="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
               ;;
            cvmAgentId)
               cvmAgentId="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
               ;;
            keyName)
               keyName="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
               ;;
            keySize)
               keySize="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
               ;;
            policyPath)
               policyPath="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
               ;;
            desName)
               desName="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
               ;;
            deployName)
               deployName="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
               ;;
            desArmTemplate)
               desArmTemplate="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
               ;;
            *)
               echo "Unknown option --${OPTARG}"
               exit 1
               ;;
         esac;;
      \?)
         echo "Invalid option: -${OPTARG}"
         exit 1
         ;;
   esac
done


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

