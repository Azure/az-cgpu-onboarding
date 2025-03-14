# ----------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ----------------------------------------------------------------------------
#
# This Module helps build release packages for az-cgpu-onboarding.
#

# Generates a 'Drop' folder that contains all 3 release packages:
# 1: cgpu-onboarding-package.tar.gz containing VM bring-up scripts, driver, and local verifier
# 2: cgpu-h100-auto-onboarding-windows.zip containing windows onboarding script with onboarding package
# 3: cgpu-h100-auto-onboarding-linux.tar.gz containing linux onboarding script with onboarding package

# Set all locations and paths
$DropFolder = "$PSScriptRoot\..\..\drops"
$PackageFolder = "$PSScriptRoot\..\..\packages"
$CgpuOnboardingPackageFolder = "cgpu-onboarding-package"
$cgpuOnboardingPackage = "cgpu-onboarding-package.tar.gz"
$H100Package = "cgpu-h100-auto-onboarding-linux"
$packageDestination = "${DropFolder}\${CgpuOnboardingPackageFolder}"
$H100PackageDestination = "${DropFolder}\${H100Package}"

function Cleanup {
	# Removes if there are any old packages before starting
	Write-Output "Cleaning up"
	if (Test-Path $DropFolder -PathType Container) {
		Remove-Item -LiteralPath $DropFolder -Force -Recurse
	}
}

function Build-Packages {
	Write-Output "Building Packages"

	# Creates folder for final packages
	if (!(Test-Path $DropFolder -PathType Container)) {
		New-Item -ItemType Directory -Force -Path $DropFolder
	}

	if (!(Test-Path $DropFolder\$CgpuOnboardingPackageFolder -PathType Container)) {
		New-Item -ItemType Directory -Force -Path $DropFolder\$CgpuOnboardingPackageFolder
	}

	# Creates cgpu-onboarding-package.tar.gz package
	Make-Cgpu-Onboarding-Package

	# Creates H100 scenario packages
	Make-H100-Packages

	# Cleans up folders
	Remove-Item $CgpuOnboardingPackageFolder -Force -Recurse
	Remove-Item $H100Package -Force -Recurse
}

function Make-Cgpu-Onboarding-Package {
	# Lists out all folders to be included as .tar in cgpu onboarding package
	[String[]]$foldersToTar = "$PSScriptRoot\..\local_gpu_verifier", 
		"$PSScriptRoot\..\local_gpu_verifier_http_service"

	# Ensures shell scripts under the folders will be in correct UNIX format
	foreach ($folder in $foldersToTar) {
		Get-ChildItem $folder -Recurse | ForEach-Object {
			$extn = [IO.Path]::GetExtension($_.FullName)
			if ($extn -eq ".sh" ) {
				((Get-Content $_.FullName) -join "`n") + "`n" | Set-Content -NoNewline $_.FullName
			}
		}
	}
	
	# Make tar to drop folder. Add result tar file to a list
	[String[]]$tarFiles = @()
	foreach ($folder in $foldersToTar) {
		$tarFilePath = "$DropFolder\$($folder.Split("\")[-1]).tar"
		Write-Output "Generating $tarFilePath"
		tar -cvf $tarFilePath -C $folder .
		$tarFiles += $tarFilePath
	}

	# Lists out all files to be included in .tar.gz archive
	Set-Location "$PSScriptRoot"
	[String[]]$files = "$PSScriptRoot\..\step-0-prepare-kernel.sh", 
		"$PSScriptRoot\..\step-1-install-gpu-driver.sh", 
		"$PSScriptRoot\..\step-2-attestation.sh", 
		"$PSScriptRoot\..\step-3-install-gpu-tools.sh", 
		"$PSScriptRoot\..\utilities-update-kernel.sh",
		"$PSScriptRoot\..\utilities-uninstall-r535-driver.sh",
		"$PSScriptRoot\..\utilities-install-openssl.sh",
		"$PSScriptRoot\..\utilities-install-local-gpu-verfier-service.sh",
		"$PSScriptRoot\..\nvidia-lkca.conf",
		"$PSScriptRoot\..\mnist-sample-workload.py", 
		"$PSScriptRoot\..\version.txt"
	$files += $tarFiles

	# Ensures each file will be in correct UNIX format
	foreach ($file in $files) {
		$extn = [IO.Path]::GetExtension($file)
		if ($extn -eq ".sh" ) {
			((Get-Content $file) -join "`n") + "`n" | Set-Content -NoNewline $file
		}
		Copy-Item $file -Destination $packageDestination -Force
	}

	# Creates main .tar.gz
	Write-Output "Generating cgpu-onboarding-package.tar.gz"
	tar -czvf $cgpuOnboardingPackage -C $DropFolder $CgpuOnboardingPackageFolder
	Move-Item $cgpuOnboardingPackage $DropFolder -Force

	# Clean up folder tar files
	foreach ($tarFile in $tarFiles) {
		Remove-Item $tarFile -Force -Recurse
	}
}

function Make-H100-Packages {
	# Generate windows (zip) H100 package
	Write-Output "Generating windows package"
	if (!(Test-Path $DropFolder\$H100Package -PathType Container)) {
		New-Item -ItemType Directory -Force -Path $H100PackageDestination
	}
	Copy-Item $DropFolder\$cgpuOnboardingPackage -Destination $H100PackageDestination -Force

	$onboardingPowershellScript = "$PSScriptRoot\..\cgpu-h100-auto-onboarding.ps1"
	$cmkPowershellScript = "$PSScriptRoot\..\cmk_module\Windows\cgpu-deploy-cmk-des.psm1"

	[String[]]$powershellScriptList = $onboardingPowershellScript, $cmkPowershellScript

	foreach ($powershellScript in $powershellScriptList) {
		if (Get-Content $powershellScript -Delimiter "`0" | Select-String "[^`r]`n") {
			$content = Get-Content $powershellScript
			$content | Set-Content $powershellScript
		}
	}

	Compress-Archive -Path $onboardingPowershellScript, $DropFolder\$cgpuOnboardingPackage, "$PSScriptRoot\..\cmk_module" -DestinationPath $DropFolder\cgpu-h100-auto-onboarding-windows.zip -Force

	# Generate linux (.tar.gz) H100 enabled package
	Write-Output "Generating linux package"

	$onboardingLinuxScript = "$PSScriptRoot\..\cgpu-h100-auto-onboarding.sh"
	$cmkLinuxScript = "$PSScriptRoot\..\cmk_module\Linux\cgpu-deploy-cmk-des.sh"

	[String[]]$linuxScriptList = $onboardingLinuxScript, $cmkLinuxScript

	foreach ($linuxScript in $linuxScriptList) {
		((Get-Content $linuxScript) -join "`n") + "`n" | Set-Content -NoNewline $linuxScript
	}

	Copy-Item $onboardingLinuxScript -Destination $H100PackageDestination
	Copy-Item "$PSScriptRoot\..\cmk_module" -Destination $H100PackageDestination -Recurse
	Set-Location $DropFolder
	tar -czvf "${H100Package}.tar.gz" -C $DropFolder $H100Package
}

Cleanup
Build-Packages