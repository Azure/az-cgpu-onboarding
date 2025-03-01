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
	# Make .tar of verifier
	cd "$PSScriptRoot\.."
	tar -cvf "$DropFolder\local_gpu_verifier.tar" -C "local_gpu_verifier" .
	cd "$PSScriptRoot"

	# Lists out all files to be included in .tar.gz archive
	[String[]]$files = "$PSScriptRoot\..\step-0-prepare-kernel.sh", 
		"$PSScriptRoot\..\step-1-install-gpu-driver.sh", 
		"$PSScriptRoot\..\step-2-attestation.sh", 
		"$PSScriptRoot\..\step-3-install-gpu-tools.sh", 
		"$PSScriptRoot\..\utilities-update-kernel.sh",
		"$PSScriptRoot\..\utilities-uninstall-r535-driver.sh",
		"$PSScriptRoot\..\nvidia-lkca.conf",
		"$PSScriptRoot\..\mnist-sample-workload.py", 
		"$PSScriptRoot\..\version.txt", 
		"$DropFolder\local_gpu_verifier.tar"

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

	# Clean up local verifier tar
	Remove-Item "$DropFolder\local_gpu_verifier.tar" -Force -Recurse
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