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
   $mdFiles = Get-ChildItem -Path "..\..\" -Filter *.md
   $mdFiles += Get-Item -Path "..\cgpu-h100-auto-onboarding.ps1"
   $mdFiles += Get-Item -Path "..\cgpu-h100-auto-onboarding.sh"

   Write-Output $mdFiles

   foreach ($file in $mdFiles) {
        $oldVersion = "V3.0.10"
    
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
$newVersion = Get-Content -Path "release_version.txt"

# Replaces occurrences in all .md and onboarding script files
Replace-Release-Versions