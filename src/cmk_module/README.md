# CMK Deployment

- Deploy CMK DES first if you need a CMK VM
- You can use our deployDES.json and skr-policy.json, or define your own

## On Linux Bash shell

- Define Parameters
```
resourceGroup="CMK-rg"
keyVault="CMK-kv"
policyPath="skr-policy.json"
desName="CMK-des"
deployName="CMK-desdeploy"
desArmTemplate="deployDES.json"
subscriptionId="<Your Subcription ID>"
region="<Your Region>"
```

- Call the script with the parameters
```
bash .\Linux\cgpu-deploy-cmk-des.sh \ 
  -subscriptionId $subscriptionId \
  -region $region \
  -resourceGroup $resourceGroup \
  -keyVault $keyVault \
  -policyPath $policyPath \
  -desName $desName `
  -deployName $deployName `
  -desArmTemplate $desArmTemplate
```

## On Windows Powershell

- Import Module
```
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module -Name .\Windows\cgpu-deploy-cmk-des.psm1 -Force -DisableNameChecking
```

- Define Parameters
```
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
```

- Call the function with the parameters
```
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
```
