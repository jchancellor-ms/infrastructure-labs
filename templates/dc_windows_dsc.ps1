#create the temp directory
New-Item -Path 'c:\temp' -ItemType Directory -ErrorAction SilentlyContinue
set-location -Path 'c:\temp'

###Configure the LCM
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
        }
    }
}

Write-Host "Creating LCM mof"
lcmConfig -InstanceName localhost -OutputPath .\lcmConfig
Set-DscLocalConfigurationManager -Path .\lcmConfig -Verbose

###Build the DSC configuration

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name ActiveDirectoryDsc -Force -AllowClobber
Install-Module -Name DnsServerDsc -Force -AllowClobber
Install-Module -Name SecurityPolicyDsc -Force -AllowClobber
Install-Module -Name ComputerManagementDsc -Force -AllowClobber

Configuration dc {
    #########################################################################
    # Import the DSC modules used in the configuration
    ########################################################################
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName DnsServerDsc
    Import-DscResource -ModuleName SecurityPolicyDsc
    Import-DscResource -ModuleName ComputerManagementDsc
    Import-DSCResource -Name WindowsFeature

    [pscredential]$credObject = New-Object System.Management.Automation.PSCredential (${adminUserName}, (ConvertTo-SecureString ${adminPassword} -AsPlainText -Force))

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

        ADDomain 'thisDomain'
        {
            DomainName                    = '${active_directory_domain}'
            Credential                    = $credObject
            SafemodeAdministratorPassword = $credObject
            ForestMode                    = 'WinThreshold'
            DomainMode                    = 'WinThreshold'
            DomainNetBiosName             = '${active_directory_netbios_name}'
            DependsOn                     = "[WindowsFeature]ADDSInstall"
        }
        #Set the KDS root key
        ADKDSKey 'LabKDSRootKey'
        {
            Ensure                   = 'Present'
            EffectiveTime            = ((get-date).addhours(-10))
            AllowUnsafeEffectiveTime = $true # Use with caution
            DependsOn                = "[ADDomain]thisDomain"
        }

        ADUser '${app_ad_user}'
        {
            Ensure              = 'Present'
            UserName            = '${app_ad_user}'
            Password            = (ConvertTo-SecureString -AsPlainText "${app_ad_user_pass}" -Force) 
            PasswordNeverResets = $true
            DomainName          = '${active_directory_domain}'
            Path                = 'CN=Users,DC=${active_directory_netbios_name},DC=com'
            DependsOn                = "[ADDomain]thisDomain"
        }

        #create a group for the GMSA user(s)
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
            DependsOn                = "[ADDomain]thisDomain"
        }

        #create a GMSA account
        ADManagedServiceAccount 'TestGmsaAccount'
        {
            Ensure             = 'Present'
            ServiceAccountName = '${gmsa_account_name}'
            AccountType        = 'Group'
            ManagedPasswordPrincipals = '${gmsa_group_name}'
            DependsOn                = "[ADKDSKey]LabKDSRootKey"

        }

        #assign a host SPN to the GMSA account
        ADServicePrincipalName 'GmsaHostShort'
        {
            ServicePrincipalName = 'host/${gmsa_account_name}'
            Account              = '${gmsa_account_name}$'
            DependsOn            = "[ADManagedServiceAccount]TestGmsaAccount"
        }
        #Create a regular user for use by the plugin to access the GMSA        
        
    }
}

#build the MOF
dc
#run the DSC configuration
Start-dscConfiguration -Path ./dc -Force

