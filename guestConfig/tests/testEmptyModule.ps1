$Params = @{
    name = 'emptyModule'
    Module   = 'emptyModule'
    Property = @{
        ConfigurationScope  = 'Machine'
        Ensure              = 'Present'
    }

}

import-Module ./modules/emptyModule/
Invoke-DscResource @Params -Method Get
#Get-GuestConfigurationPackageComplianceStatus -Path ./packages/installAzCliLinux.zip -Parameter $Params