# ----------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ----------------------------------------------------------------------------
#
# This Module helps build release packages for PrivatePreview.
#

# Generates a 'Drop' folder that contains all 3 release packages:
# 1: cgpu-onboarding-package.tar.gz containing VM bring-up scripts, driver, and verifier
# 2: cgpu-sb-enable-vmi-onboarding.zip containing windows onboarding script with onboarding package
# 3: cgpu-sb-enable-vmi-onboarding.tar.gz containing linux onboarding script with onboarding package

# Set all locations and paths
$DropFolder="$PSScriptRoot\..\..\drops"
$PackageFolder="$PSScriptRoot\..\..\packages"
$CgpuOnboardingPackageFolder="cgpuOnboardingPackage"
$cgpuOnboardingPackage="cgpu-onboarding-package.tar.gz"
$SbEnabledPackage="cgpu-sb-enable-vmi-onboarding"
$packageDestination = "${DropFolder}\${CgpuOnboardingPackageFolder}"
$SbEnabledPackageDestination="${DropFolder}\${SbEnabledPackage}"

function Build-Packages {
	echo "Building Packages"
	# Creates folder for final packages
	if (!(Test-Path $DropFolder -PathType Container)) {
		New-Item -ItemType Directory -Force -Path $DropFolder
	}

	if (!(Test-Path $DropFolder\$CgpuOnboardingPackageFolder -PathType Container)) {
		New-Item -ItemType Directory -Force -Path $DropFolder\$CgpuOnboardingPackageFolder
	}

	# Creates cgpu-onboarding-package.tar.gz package
	Make-Cgpu-Onboarding-Package

	# Creates secureboot-enabled scenario packages
	Make-Sb-Enabled-Packages

	# Cleans up folders
	Remove-Item $CgpuOnboardingPackageFolder -Force -Recurse
	Remove-Item $SbEnabledPackage -Force -Recurse
}

function Make-Cgpu-Onboarding-Package {
	# Lists out all files to be included in .tar.gz archive
	[String[]]$files = "$PSScriptRoot\..\step-0-enroll-signing-key.sh", "$PSScriptRoot\..\step-1-install-gpu-driver.sh", 
		"$PSScriptRoot\..\step-2-attestation.sh", "$PSScriptRoot\..\step-3-install-gpu-tools.sh", "$PSScriptRoot\..\utilities-update-kernel.sh",
		"$PSScriptRoot\..\mnist-sample-workload.py", "$PSScriptRoot\..\nvidia.pref", "${PackageFolder}\APM_470.10.12_5.15.0-1014.17.tar",
		"${PackageFolder}\verifier_apm_pid3_5_1.tar", "${PackageFolder}\linux_kernel_apm_sha256_cert.pem"

	# Ensures each file will be in correct UNIX format
	foreach($file in $files) {
		$extn = [IO.Path]::GetExtension($file)
		if ($extn -eq ".sh" ){
			((Get-Content $file) -join "`n") + "`n" | Set-Content -NoNewline $file
		}
		Copy-Item $file -Destination $packageDestination -Force
	}

	# Creates main .tar.gz
	echo "generating customer-onboarding-package.tar.gz"
	tar -czvf $cgpuOnboardingPackage -C $packageDestination .
	Move-Item $cgpuOnboardingPackage $DropFolder -Force
}

function Make-Sb-Enabled-Packages {
	# Generate windows (zip) secure-boot enabled package
	echo "generating windows package"
	if (!(Test-Path $DropFolder\$SbEnabledPackage -PathType Container)) {
		New-Item -ItemType Directory -Force -Path $SbEnabledPackageDestination
	}
	$powershellScript="$PSScriptRoot\..\secureboot-enable-onboarding-from-vmi.ps1"
	Copy-Item $DropFolder\$cgpuOnboardingPackage -Destination $SbEnabledPackageDestination -Force
	if (Get-Content $powershellScript -Delimiter "`0" | Select-String "[^`r]`n")
    {
        $content = Get-Content $powershellScript
        $content | Set-Content $powershellScript
    }
	Copy-Item "$powershellScript" -Destination $SbEnabledPackageDestination -Force
	Compress-Archive -Path $SbEnabledPackageDestination -DestinationPath $DropFolder\cgpu-sb-enable-vmi-onboarding.zip -Force

	# Generate linux (.tar.gz) secure-boot enabled package
	"generating linux package"
	Remove-Item ${SbEnabledPackageDestination}\secureboot-enable-onboarding-from-vmi.ps1
	$linuxScript="$PSScriptRoot\..\secureboot-enable-onboarding-from-vmi.sh"
	$extn = [IO.Path]::GetExtension("${SbEnabledPackageDestination}\${linuxScript}")
	((Get-Content $linuxScript) -join "`n") + "`n" | Set-Content -NoNewline $linuxScript
	Copy-Item $linuxScript -Destination $SbEnabledPackageDestination
	Set-Location $DropFolder
	tar -czvf "${SbEnabledPackage}.tar.gz" -C $SbEnabledPackage .
}

Build-Packages