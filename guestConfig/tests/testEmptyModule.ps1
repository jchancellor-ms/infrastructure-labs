$Params = @{
    name = 'emptyModule'
    Module   = 'emptyModule'
    Property = @{
        Name                = 'Test'
        Ensure              = 'Present'
    }

}

import-Module ./modules/emptyModule/
Invoke-DscResource @Params -Method Get -Verbose
#Get-GuestConfigurationPackageComplianceStatus -Path ./packages/installAzCliLinux.zip -Parameter $Params