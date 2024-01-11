<#
  ##Sample Parameters:
  $timeString = Get-Date -Format "HHmmss"
  $subscriptionId = "85c61f94-8912-4e82-900e-6ab44de9bdf8"
  $region = "eastus2"
  $resourceGroup ="$($timeString)-CMK-rg"
  $keyName = "$($timeString)-CMK-key"
  $keyVault = "$($timeString)-CMK-kv"
  $policyPath = "skr-policy-2.json"
  $desName = "$($timeString)-CMK-des"
  $deployName = "$($timeString)-CMK-desdeploy"
  $desArmTemplate = "deployDES.json"

  ##Sample Command:
  DEPLOY-CMK-DES `
  -subscriptionId $subscriptionId `
  -region $region `
  -resourceGroup $resourceGroup `
  -keyName $keyName `
  -keyVault $keyVault `
  -policyPath $policyPath `
  -desName $desName `
  -deployName $deployName `
  -desArmTemplate $desArmTemplate
#>

function DEPLOY-CMK-DES{
  param(
    $subscriptionId,
    $region="eastus2",
    $resourceGroup,
    $keyVault,
    $cvmAgentId="bf7b6499-ff71-4aa2-97a4-f372087be7f0",
    $keyName,
    $keySize=3072,
    $policyPath,
    $desName,
    $deployName,
    $desArmTemplate
  )

  az login
  az account set --subscription $subscriptionid
  Write-Host "---------------------------------- Login to [$($subscriptionId)] ----------------------------------"

  az group create --name $resourceGroup --location $region
  az keyvault create --name $keyVault --resource-group $resourceGroup --location $region --sku Premium --enable-purge-protection 
  Write-Host "---------------------------------- Keyvault [$($keyVault)] created ----------------------------------"

  $cvmAgent = az ad sp show --id $cvmAgentId | Out-String | ConvertFrom-Json
  az keyvault set-policy --name $keyVault --resource-group $resourceGroup --object-id $cvmAgent.id --key-permissions get release
  az keyvault key create --vault-name $keyVault --name $keyName --ops wrapKey unwrapkey --kty RSA-HSM --size $keySize --exportable true --policy $policyPath
  Write-Host "---------------------------------- KeyName [$($keyName)] created ----------------------------------"

  $encryptionKeyVaultId = ((az keyvault show -n $keyVault -g $resourceGroup) | ConvertFrom-Json).id
  $encryptionKeyURL= ((az keyvault key show --vault-name $keyVault --name $keyName) | ConvertFrom-Json).key.kid
  Write-Host "---------------------------------- KeyVaultId [$($encryptionKeyVaultId)] ----------------------------------"

  az deployment group create `
    -g $resourceGroup `
    -n $deployName `
    -f $desArmTemplate `
    -p desName=$desName `
    -p encryptionKeyURL=$encryptionKeyURL `
    -p encryptionKeyVaultId=$encryptionKeyVaultId `
    -p region=$region
  Write-Host "---------------------------------- Des deployment [$($desName)] created ----------------------------------"
  
  $desIdentity= (az disk-encryption-set show -n $desName -g $resourceGroup --query [identity.principalId] -o tsv)
  Write-Host "---------------------------------- desIdentity [$($desIdentity)] retrieved ----------------------------------"

  az keyvault set-policy -n $keyVault `
    -g $resourceGroup `
    --object-id $desIdentity `
    --key-permissions wrapkey unwrapkey get
  Write-Host "---------------------------------- Set policy ----------------------------------"

  $desID = (az disk-encryption-set show -n $desName -g $resourceGroup --query [id] -o tsv)
  Write-Host "---------------------------------- [$($desID)] is the desID ----------------------------------"
  
}



