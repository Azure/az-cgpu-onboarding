# CMK Deployment

- Deploy CMK DES first if you need a CMK VM
- You can use our deployDES.json and skr-policy.json, or define your own

## On Linux Bash shell

- Call bash script
```
bash Linux/cgpu-deploy-cmk-des.sh \
-s "85c61f94-8912-4e82-900e-6ab44de9bdf8" \
-t "72f988bf-86f1-41af-91ab-2d7cd011db47" \
-r "eastus2" \
-g "cmk-$(date +"%H%M%S")-rg" \
-k "cmk-$(date +"%H%M%S")-key" \
-v "cmk-$(date +"%H%M%S")-kv" \
-p "skr-policy.json" \
-d "cmk-$(date +"%H%M%S")-desdeploy" \
-n "cmk-$(date +"%H%M%S")-des" \
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
  $timeString = Get-Date -Format "HHmmss"
  $subscriptionId = "85c61f94-8912-4e82-900e-6ab44de9bdf8"
  $tenantId = "72f988bf-86f1-41af-91ab-2d7cd011db47"
  $region = "eastus2"
  $resourceGroup ="CMK-$($timeString)-rg"
  $keyName = "CMK-$($timeString)-key"
  $keyVault = "CMK-$($timeString)-kv"
  $policyPath = "skr-policy.json"
  $desName = "CMK-$($timeString)-des"
  $deployName = "CMK-$($timeString)-desdeploy"
  $desArmTemplate = "deployDES.json"
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
