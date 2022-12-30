Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name ActiveDirectoryDsc -Force -AllowClobber
Install-Module -Name DnsServerDsc -Force -AllowClobber
Install-Module -Name SecurityPolicyDsc -Force -AllowClobber
Install-Module -Name ComputerManagementDsc -Force -AllowClobber
Install-Module -Name CredentialSpec -Force -AllowClobber