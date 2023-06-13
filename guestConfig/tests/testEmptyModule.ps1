$Params = @{
    Name = "localhost"
    Ensure = Present
}

Get-GuestConfigurationPackageComplianceStatus -Path ./packages/installAzCliLinux.zip -Parameter $Params