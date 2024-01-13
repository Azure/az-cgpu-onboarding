#!/bin/bash

# Update the list of packages
sudo apt-get update

# Install pre-requisite packages
sudo apt-get install -y wget apt-transport-https software-properties-common

# Download the Microsoft repository GPG keys
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"

# Register the Microsoft repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb

# Update the list of products
sudo apt-get update

# Enable the "universe" repositories
sudo add-apt-repository universe

# Install PowerShell
sudo apt-get install -y powershell

#- (Prerequisite) Set MgServicePrincipal
# You will need this step if you have not set your cvmAgentId for your tenant
az login
tenantId=$(az account show --query tenantId -o tsv)
tenantId=$(echo $tenantId | tr -cd '[:alnum:]-/,.:')

# Install Microsoft.Graph PowerShell module
sudo pwsh -Command "Install-Module Microsoft.Graph -Scope CurrentUser -Repository PSGallery"
sudo pwsh -Command "Get-Module -Name Microsoft.Graph -ListAvailable"

# Create MgServicePrincipal
sudo pwsh -Command "Connect-Graph -Tenant $tenantId -Scopes Application.ReadWrite.All"
sudo pwsh -Command "New-MgServicePrincipal -AppId bf7b6499-ff71-4aa2-97a4-f372087be7f0 -DisplayName 'Confidential VM Orchestrator'"
