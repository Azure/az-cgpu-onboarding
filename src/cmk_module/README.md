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
bash .\Linux\cgpu-deploy-cmk-des.sh deploy_cmk_des $subscriptionId $region $resourceGroup $keyVault $policyPath $desName $deployName $desArmTemplate
```

## On Windows Powershell

- Import Module
```
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module -Name .\Windows\cgpu-deploy-cmk-des.psm1 -Force -DisableNameChecking
```

- Define Parameters
```
$resourceGroup="CMK-rg"
$keyVault="CMK-kv"
$policyPath="skr-policy.json"
$desName="CMK-des"
$deployName="CMK-desdeploy"
$desArmTemplate="deployDES.json"
$subscriptionId="<Your Subcription ID>"
$region="<Your Region>"
```

- Call the function with the parameters
```
DEPLOY-CMK-DES `
  -subscriptionId $subscriptionId `
  -region $region `
  -resourceGroup $resourceGroup `
  -keyVault $keyVault `
  -policyPath $policyPath `
  -desName $desName `
  -deployName $deployName `
  -desArmTemplate $desArmTemplate
```
