# ----------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ----------------------------------------------------------------------------
#
# This Module helps build release packages for az-cgpu-onboarding.
#

# Goes through all .md documentation files and onboarding scripts to replace versions
function Replace-Release-Versions {
    Write-Output "in replace"

    # Get all .md onboarding files and onboarding scripts
    $filesToUpdate = Get-ChildItem -Path "..\..\" -Filter *.md
    $filesToUpdate += Get-Item -Path "..\cgpu-h100-auto-onboarding.ps1"
    $filesToUpdate += Get-Item -Path "..\cgpu-h100-auto-onboarding.sh"

    # Get the old version by looking at onboarding script
    $scriptContent = Get-Content "..\cgpu-h100-auto-onboarding.ps1" -Raw
    $versionPattern = 'V\d+\.\d+\.\d+'
    $patternMatch = [regex]::Match($scriptContent, $versionPattern)
    $oldVersion = $patternMatch.Value

    # Check that both the old and new versions are in the right format
    if (-not ($patternMatch.Success)) {
        throw "No valid old version found, please check format of previous version in cgpu-h100-auto-onboarding.ps1 script."
    } else {
        $oldVersion = $patternMatch.Value
        Write-Output "Old version is: $oldVersion"
    }
    if (-not ($newVersion -match $versionPattern)) {
        throw "The format of the version in version.txt is invalid. Please make sure it follows this example syntax: V3.0.1"
    } else {
        Write-Output "New version is: $newVersion"
    }

    foreach ($file in $filesToUpdate) {    
        # Read the content of the file
        $content = Get-Content -Path $file.FullName

        # Replace occurrences of the old version with the new version
        $updatedContent = $content -replace [regex]::Escape($oldVersion), $newVersion

        # Write the updated content back to the file
        Set-Content -Path $file.FullName -Value $updatedContent

        # Output the file processed (optional)
        Write-Output "Finished updating: $file"
    }
}

# Gets the release version from release_version.txt
$newVersion = Get-Content -Path "..\version.txt"

# Replaces occurrences in all .md and onboarding script files
Replace-Release-Versions