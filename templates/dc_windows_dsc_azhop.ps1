New-Item -Path 'c:\temp' -ItemType Directory -ErrorAction SilentlyContinue
set-location -Path 'c:\temp'

$cert = Get-ChildItem -Path cert:\LocalMachine\My\${dsc_cert_thumbprint}
Export-Certificate -Cert $cert -FilePath .\dsc.cer
certutil -encode dsc.cer dsc64.cer

[DSCLocalConfigurationManager()]
Configuration lcmConfig {
    Node localhost
    {
        Settings
        {
            RefreshMode = 'Push'
            ActionAfterReboot = "ContinueConfiguration"
            RebootNodeIfNeeded = $true
            ConfigurationModeFrequencyMins = 15
            CertificateID = "${dsc_cert_thumbprint}"
        }
    }
}

Write-Host "Creating LCM mof"
lcmConfig -InstanceName localhost -OutputPath .\lcmConfig
Set-DscLocalConfigurationManager -Path .\lcmConfig -Verbose

Configuration dc {
   
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName DnsServerDsc
    Import-DscResource -ModuleName SecurityPolicyDsc
    Import-DscResource -ModuleName ComputerManagementDsc
    Import-DSCResource -Name WindowsFeature

    [pscredential]$credObject = New-Object System.Management.Automation.PSCredential ("${admin_username}", (ConvertTo-SecureString "${admin_password}" -AsPlainText -Force))

    Node localhost
    {
        #Add the containers and hypervisor features and reboot if needed 
        WindowsFeature 'ad-domain-services'
        {
            Name                 = 'ad-domain-services'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        WindowsFeature 'dns'
        {
            Name                 = 'dns'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        WindowsFeature 'rsat-dns-server'
        {
            Name                 = 'rsat-dns-server'
            Ensure               = 'Present'
        }

        WindowsFeature 'rsat-adds'
        {
            Name                 = 'rsat-adds'
            Ensure               = 'Present'
        }

        WindowsFeature 'rsat-ad-powershell'
        {
            Name                 = 'rsat-ad-powershell'
            Ensure               = 'Present'
        }

        DnsServerForwarder 'SetForwarders'
        {
            IsSingleInstance = 'Yes'
            IPAddresses      = @('8.8.8.8', '168.63.129.16')
            UseRootHint      = $false
            DependsOn        = "[WindowsFeature]dns"
        }

        ADDomain 'thisDomain'
        {
            DomainName                    = '${active_directory_domain}'
            Credential                    = $credObject
            SafemodeAdministratorPassword = $credObject
            ForestMode                    = 'WinThreshold'
            DomainMode                    = 'WinThreshold'
            DomainNetBiosName             = '${active_directory_netbios_name}'
            DependsOn                     = "[WindowsFeature]ad-domain-services"
        } 
        
        WaitForADDomain 'thisDomain'
        {
            DomainName = '${active_directory_domain}'
        }


        #write the domain values to the key vault to populate the credential spec template later
        script 'uploadDomainInfoToKeyVault' {
            DependsOn            = "[WaitForADDomain]thisDomain"
            GetScript            = { return @{result = 'Writing Domain GUID and SID to keyvault' } }
            TestScript           = { 
                Connect-AzAccount -Identity | Out-Null
                $domainInfo = get-AdDomain -errorAction SilentlyContinue
                $Sid = Get-AzKeyVaultSecret -vaultName "${vault_name}" -Name "domain-sid" -AsPlainText -errorAction SilentlyContinue
                $Guid = Get-AzKeyVaultSecret -vaultName "${vault_name}" -Name "domain-guid" -AsPlainText -errorAction SilentlyContinue
                if (($domainInfo.DomainSid.value.toUpper() -ne $Sid) -or ($domainInfo.ObjectGuid.Guid.toUpper() -ne $Guid)) { 
                    $return = $false 
                }
                else {
                    $return = $true
                }
                
                return $return 
                #return $true
            }
            SetScript            = {                    
                Connect-AzAccount -Identity | Out-Null
                $domainInfo = get-AdDomain
                $Sid = convertTo-SecureString -String $domainInfo.DomainSid.value.toUpper() -AsPlainText -Force
                $Guid = convertTo-SecureString -String $domainInfo.ObjectGuid.Guid.toUpper -AsPlainText -Force
                Set-AzKeyVaultSecret -vaultName "${vault_name}" -Name "domain-sid" -SecretValue $Sid
                Set-AzKeyVaultSecret -vaultName "${vault_name}" -Name "domain-guid" -SecretValue $Guid
            }
        }       
        
    }
}

$cd = @{
    AllNodes = @(    
        @{ 
            NodeName = "localhost"
            CertificateFile = "C:\temp\dsc64.cer"
            Thumbprint = "${dsc_cert_thumbprint}"
        }
    ) 
}
dc -ConfigurationData $cd
Start-dscConfiguration -Path ./dc -Force

