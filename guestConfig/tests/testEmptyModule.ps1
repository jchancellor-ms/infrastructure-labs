$Params = @{
    name = "localhost"
    ensure = "Present"
}

Invoke-DscResource @Params -Method Get
#Get-GuestConfigurationPackageComplianceStatus -Path ./packages/installAzCliLinux.zip -Parameter $Params