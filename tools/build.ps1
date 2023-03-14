# ----------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ----------------------------------------------------------------------------
#
# This Module helps build release packages for PrivatePreview.
#

# Generates a 'Drop' folder that contains all 3 release packages:
# 1: cgpu-onboarding-package.tar.gz containing vm bring-up scripts, driver, and verifier
# 2: cgpu-sb-enable-vmi-onboarding.zip containing windows onboarding script with onboarding package
# 3: cgpu-sb-enable-vmi-onboarding.tar.gz containing linux onboarding script with onboarding package

# Set all locations and paths
$DropFolder="Drop"
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
	[String[]]$files = "..\src\step-0-enroll-signing-key.sh", "..\src\step-1-install-gpu-driver.sh", 
		"..\src\step-2-attestation.sh", "..\src\step-3-install-gpu-tools.sh", "..\src\utilities-update-kernel.sh",
		"..\src\mnist-sample-workload.py", "..\src\nvidia.pref", ".\blobs\APM_470.10.12_5.15.0-1014.17.tar",
		".\blobs\verifier_apm_pid3_5_1.tar"
	foreach($file in $files) {
		Copy-Item $file -Destination $packageDestination -Force
	}

	# Creates main .tar.gz
	tar -czvf $cgpuOnboardingPackage -C $packageDestination .
	Move-Item $cgpuOnboardingPackage $DropFolder -Force
}

function Make-Sb-Enabled-Packages {
	# Generate windows (zip) secure-boot enabled package
	echo "generating windows package"
	if (!(Test-Path $DropFolder\$SbEnabledPackage -PathType Container)) {
		New-Item -ItemType Directory -Force -Path $SbEnabledPackageDestination
	}
	Copy-Item $DropFolder\$cgpuOnboardingPackage -Destination $SbEnabledPackageDestination -Force
	Copy-Item "..\src\secureboot-enable-onboarding-from-vmi.ps1" -Destination $SbEnabledPackageDestination -Force
	Compress-Archive -Path $SbEnabledPackageDestination -DestinationPath $DropFolder\cgpu-sb-enable-vmi-onboarding.zip -Force

	# Generate linux (.tar.gz) secure-boot enabled package
	"generating linux package"
	Copy-Item "..\src\secureboot-enable-onboarding-from-vmi.sh" -Destination $SbEnabledPackageDestination
	Remove-Item ${SbEnabledPackageDestination}\secureboot-enable-onboarding-from-vmi.ps1
	Set-Location $DropFolder
	tar -czvf "${SbEnabledPackage}.tar.gz" -C $SbEnabledPackage .
}