# CMK Deployment

- Deploy CMK DES first if you need a CMK VM
- You can use our deployDES.json and skr-policy.json, or define your own

## On Linux Bash shell

- Call bash script
```
bash Linux/cgpu-deploy-cmk-des.sh \
-s "<subscriptionId>" \
-t "<tenantId>" \
-r "eastus2" \
-g "cmk-$(date +"%Y%m%d%H%M%S")-rg" \
-k "cmk-$(date +"%Y%m%d%H%M%S")-key" \
-v "cmk-$(date +"%Y%m%d%H%M%S")-kv" \
-p "skr-policy.json" \
-d "cmk-$(date +"%Y%m%d%H%M%S")-desdeploy" \
-n "cmk-$(date +"%Y%m%d%H%M%S")-des" \
-m "deployDES.json"
```

## On Windows Powershell

- Import Module
```
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module -Name .\Windows\cgpu-deploy-cmk-des.psm1 -Force -DisableNameChecking
```

- Define Parameters
```
  # Put your own subsctripionId and tenantId here
  $subscriptionId = "<Your subsctripionId>"
  $tenantId = "<Your tenantId>"

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
