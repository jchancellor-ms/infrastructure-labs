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
    [pscredential]$gmsaAppCred = New-Object System.Management.Automation.PSCredential ("${app_ad_user}", (ConvertTo-SecureString "${app_ad_user_pass}" -AsPlainText -Force))

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

        WindowsFeature 'rsat-adds'
        {
            Name                 = 'rsat-adds'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        WindowsFeature 'rsat-ad-powershell'
        {
            Name                 = 'rsat-ad-powershell'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
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

        ADUser '${app_ad_user}'
        {
            Ensure              = 'Present'
            UserName            = '${app_ad_user}'
            Password            = $gmsaAppCred
            PasswordNeverResets = $true
            DomainName          = '${active_directory_domain}'
            Path                = 'CN=Users,DC=${active_directory_netbios_name},DC=com'
            DependsOn                = "[WindowsFeature]ad-domain-services", "[ADDomain]thisDomain"
        }

        ADGroup 'GmsaGroup'
        {
            GroupName   = '${gmsa_group_name}'
            GroupScope  = 'Global'
            Category    = 'Security'
            Description = 'Sample gmsa security group'
            Ensure      = 'Present'
            MembersToInclude = @(
                '${active_directory_netbios_name}\${app_ad_user}'
            )
            DependsOn                = "[WindowsFeature]ad-domain-services", "[ADDomain]thisDomain"
        }

        ADKDSKey 'LabKDSRootKey'
        {
            Ensure                   = 'Present'
            EffectiveTime            = ((get-date).addhours(-10))
            AllowUnsafeEffectiveTime = $true # Use with caution
            DependsOn                = "[WindowsFeature]ad-domain-services", "[ADDomain]thisDomain"
        }

        ADManagedServiceAccount 'TestGmsaAccount'
        {
            Ensure             = 'Present'
            ServiceAccountName = '${gmsa_account_name}'
            AccountType        = 'Group'
            ManagedPasswordPrincipals = '${gmsa_group_name}'
            DependsOn                = "[ADKDSKey]LabKDSRootKey", "[ADDomain]thisDomain", "[WindowsFeature]ad-domain-services"

        }

        ADServicePrincipalName 'GmsaHostShort'
        {
            ServicePrincipalName = 'host/${gmsa_account_name}'
            Account              = '${gmsa_account_name}$'
            DependsOn            = "[ADManagedServiceAccount]TestGmsaAccount", "[ADKDSKey]LabKDSRootKey", "[ADDomain]thisDomain", "[WindowsFeature]ad-domain-services"
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

