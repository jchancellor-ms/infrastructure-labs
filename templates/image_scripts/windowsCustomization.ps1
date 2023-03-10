param (
  [CmdletBinding()]

  [Parameter(Mandatory = $true)]
  # key vault name holding cert
  [string]$keyVaultName = $null,

  [Parameter(Mandatory = $false)]
  # certname for the cert in the key vault
  [string]$spCertName = $null
)


#install the az cli
$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; Remove-Item .\AzureCLI.msi

#install the az powershell 
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force


#reload the path
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") 



#login as the managed identity
az login --identity --allow-no-subscriptions

#download the extension install SP certificate 
az keyvault certificate download --vault-name $keyVaultName -n $spCertName -f c:\temp\cert.crt -e DER

#install anti-malware extension


