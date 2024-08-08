<#
- Import Module
```
cd <Repo Path>\src\cmk_module
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module -Name .\Windows\cgpu-deploy-cmk-des.psm1 -Force -DisableNameChecking
```

- Define Parameters
```
  # Put your own subsctripionId and tenantId here
  $subscriptionId = "85c61f94-8912-4e82-900e-6ab44de9bdf8"
  $tenantId = "72f988bf-86f1-41af-91ab-2d7cd011db47"

  # Default parameters
  $region = "eastus2"
  $desArmTemplate = "deployDES.json"
  $policyPath = "skr-policy.json"

  # Auto generate the resource group name, key name, key vault name, des name, des deployment name from the current time
  $timeString = Get-Date -Format "yyyyMMddHHmmss"
  $resourceGroup ="CMK-$($timeString)-rg"
  $keyName = "CMK-$($timeString)-key"
  $keyVault = "CMK-$($timeString)-kv" 
  $desName = "CMK-$($timeString)-des"
  $deployName = "CMK-$($timeString)-desdeploy"
  
```

- Call the function with the parameters
```
DEPLOY-CMK-DES `
  -subscriptionId $subscriptionId `
  -tenantId $tenantId `
  -region $region `
  -resourceGroup $resourceGroup `
  -keyName $keyName `
  -keyVault $keyVault `
  -policyPath $policyPath `
  -desName $desName `
  -deployName $deployName `
  -desArmTemplate $desArmTemplate
```
#>

function SET-SERVICEPRINCIPAL {

  param(
    $tenantId="72f988bf-86f1-41af-91ab-2d7cd011db47",
    $cvmAgentId="bf7b6499-ff71-4aa2-97a4-f372087be7f0",
    $cvmAgentName="Confidential VM Orchestrator"
  )

  # check for service principal existence
  $servicePrincipal = az ad sp show --id $cvmAgentId | Out-String | ConvertFrom-Json

  if ($null -ne $servicePrincipal) {
    Write-Output "----------------------------------  Service Principal exists, SKIP ---------------------------------- "
  } 
  else {

    Write-Output "----------------------------------  Service Principal does not exist, creating ---------------------------------- "

    # Install Microsoft.Graph module
    Install-Module Microsoft.Graph -Scope CurrentUser -Repository PSGallery
    
    # Create MgServicePrincipal
    Connect-Graph -Tenant $tenantId -Scopes Application.ReadWrite.All
    New-MgServicePrincipal -AppId $cvmAgentId -DisplayName $cvmAgentName

    # Wait 300s for service principal to be created
    for ($i = 0; $i -lt 60; $i++) {
      $servicePrincipal = az ad sp show --id $cvmAgentId | Out-String | ConvertFrom-Json
      if ($cvmAgentId -eq $servicePrincipal.appId) {
        break
      }
      Write-Output "----------------------------------  Waiting for service principal $($cvmAgentId) to be created ---------------------------------- "
      Start-Sleep -s 5
    }

    Write-Output "----------------------------------  Service Principal $($servicePrincipal) created ---------------------------------- "
  }
}

function DEPLOY-CMK-DES{
  param(
    $subscriptionId,
    $tenantId,
    $region="eastus2",
    $resourceGroup="CMK-$($timeString)-rg",
    $keyVault="CMK-$($timeString)-kv",
    $cvmAgentId="bf7b6499-ff71-4aa2-97a4-f372087be7f0",
    $cvmAgentName="Confidential VM Orchestrator",
    $keyName="CMK-$($timeString)-key",
    $keySize=3072,
    $policyPath="skr-policy.json",
    $desName="CMK-$($timeString)-des",
    $deployName="CMK-$($timeString)-desdeploy",
    $desArmTemplate="deployDES.json"
  )

  az login --tenant $tenantId
  az account set --subscription $subscriptionid
  Write-Host "---------------------------------- Login to [$($subscriptionId)] ----------------------------------"

  # Install Microsoft.Graph module
  SET-SERVICEPRINCIPAL -tenantId $tenantId -cvmAgentId $cvmAgentId -cvmAgentName $cvmAgentName

  $groupExists = az group exists --name $resourceGroup
  if ($groupExists -eq "false") {
    az group create --name $resourceGroup --location $region
    Write-Host "---------------------------------- Resource group [$($resourceGroup)] created ----------------------------------"
  } else {
    Write-Host "---------------------------------- Resource group [$($resourceGroup)] already exists ----------------------------------"
  }

  az keyvault create --name $keyVault --resource-group $resourceGroup --location $region --sku Premium --enable-purge-protection --enable-rbac-authorization false
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



