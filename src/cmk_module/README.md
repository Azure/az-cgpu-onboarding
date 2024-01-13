# CMK Deployment

- Deploy CMK DES first if you need a CMK VM
- You can use our deployDES.json and skr-policy.json, or define your own

## On Linux Bash shell

#- (Prerequisite) Set MgServicePrincipal
You will need this step if you have not set your cvmAgentId for your tenant
```
bash Linux/pre-requisite.sh
```

- Call bash script
```
bash Linux/cgpu-deploy-cmk-des.sh \
-s "85c61f94-8912-4e82-900e-6ab44de9bdf8" \
-r "eastus2" \
-g "cmk-$(date +"%H%M%S")-rg" \
-k "cmk-$(date +"%H%M%S")-key" \
-v "cmk-$(date +"%H%M%S")-kv" \
-p "skr-policy.json" \
-d "cmk-$(date +"%H%M%S")-desdeploy" \
-n "cmk-$(date +"%H%M%S")-des" \
-t "deployDES.json"
```

## On Windows Powershell

- Import Module
```
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module -Name .\Windows\cgpu-deploy-cmk-des.psm1 -Force -DisableNameChecking
```

- (Prerequisite) Set MgServicePrincipal
You will need this step if you have not set your cvmAgentId for your tenant
```
SET-SERVICEPRINCIPAL
```

- Define Parameters
```
  $timeString = Get-Date -Format "HHmmss"
  $subscriptionId = "85c61f94-8912-4e82-900e-6ab44de9bdf8"
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
  -region $region `
  -resourceGroup $resourceGroup `
  -keyName $keyName `
  -keyVault $keyVault `
  -policyPath $policyPath `
  -desName $desName `
  -deployName $deployName `
  -desArmTemplate $desArmTemplate
```
