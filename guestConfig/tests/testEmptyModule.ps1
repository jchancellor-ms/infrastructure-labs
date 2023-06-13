$Params = @{
    name = "localhost"
    ensure = "Present"
}

import-Module ./modules/emptyModule/
Invoke-DscResource @Params -Method Get
#Get-GuestConfigurationPackageComplianceStatus -Path ./packages/installAzCliLinux.zip -Parameter $Params