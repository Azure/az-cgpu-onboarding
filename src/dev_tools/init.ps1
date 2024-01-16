# ----------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ----------------------------------------------------------------------------
#
# This Module helps build release packages for PrivatePreview.
#

# Downloads the GPU driver and Nvidia verifier from given Azure storage location
function Download-Blobs {
    $resourceGroup="cgpu-resources"
    $storageAccountName="cgpu"
    $container="cgpucontainer"
    $destination="$PSScriptRoot\..\..\packages"

    # Creates destination directory if it doesn't exist
    if (-not (Test-Path -Path $destination -PathType Container)) {
        New-Item -Path $destination -ItemType Directory
    }

    # Gets storage account with container to download blobs from
    #$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroup

    # Get all blobs from container
    #$blobs = Get-AzStorageBlob -Container $container -Context $storageAccount.Context | Where-Object {$_.BlobType -eq "BlockBlob"}

    # Downloads each blob into given destination
    #$blobs | Get-AzStorageBlobContent -Destination $destination -Force
    #echo "Downloaded all blobs to ${destination}"
}

# Ensures pre-reqs are installed: Azure CLI
# And logs in to Azure account
function Setup {
    # Installs Az Powershell module if not installed already
    echo "Setting up environment"
    if (Get-Module -ListAvailable -Name Az) {
        Write-Host "Az setup already"
    } 
    else {
        Write-Host "Installing Az Powershell, this may take a few minutes"
        Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
    }

    # Logs in to Azure account
    Connect-AzAccount
    Set-AzContext -SubscriptionId "85c61f94-8912-4e82-900e-6ab44de9bdf8"
}

# Starts with Setup
Setup

# Then downloads all blobs from storage container
Download-Blobs
