[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#install modules
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name PowerShellGet -Force
Install-Module -Name Az  -Repository PSGallery -Force
Install-Module -Name ActiveDirectoryDsc -Force -AllowClobber
Install-Module -Name DnsServerDsc -Force -AllowClobber
Install-Module -Name SecurityPolicyDsc -Force -AllowClobber
Install-Module -Name ComputerManagementDsc -Force -AllowClobber
Install-Module -Name CredentialSpec -Force -AllowClobber
install-module -Name 7zip4Powershell -MinimumVersion 2.0.0 -Force

#install the CLI
New-Item -Path 'c:\temp' -ItemType Directory -ErrorAction SilentlyContinue
set-location -Path 'c:\temp'
$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; rm .\AzureCLI.msi                
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")

#download the dsc script file from the keyvault
#and base64 decode the output into a script file
Connect-AzAccount -Identity
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((Get-AzKeyVaultSecret -vaultName ${vault_name} -Name ${script_name} -AsPlainText))) | Out-File -filepath dsc_script.ps1

#run the script file
.\dsc_script.ps1
 