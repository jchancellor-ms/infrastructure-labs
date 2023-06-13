$Params = @{
    name = 'installAzCliLinux'
    Module   = 'installAzCliLinux'
    Property = @{
        Name                = 'Test'
        Ensure              = 'Present'
    }

}

$env:PSModulePath += ":$($pwd)./modules"

import-Module ./modules/installAzCliLinux/
import-Module ./modules/azMachineConfigCommon/
Invoke-DscResource @Params -Method Get -Verbose
Invoke-DscResource @Params -Method Test -Verbose
Invoke-DscResource @Params -Method Set -Verbose

#Get-GuestConfigurationPackageComplianceStatus -Path ./packages/installAzCliLinux.zip -Parameter $Params