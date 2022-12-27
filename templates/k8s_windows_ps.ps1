#create the temp directory
New-Item -Path 'c:\temp' -ItemType Directory -ErrorAction SilentlyContinue
set-location -Path 'c:\temp'

#copy the dsc script file locally
#Invoke-webRequest -Uri ${dsc_uri} -outfile ${dsc_outfile}
Invoke-webRequest -Uri https://raw.githubusercontent.com/jchancellor-ms/infrastructure-labs/main/templates/k8s_windows_dsc.ps1 -outfile .\k8s_windows_dsc.ps1


#execute the dsc configuration
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
lcmConfig -NodeName localhost -OutputPath .\lcmConfig
Set-DscLocalConfigurationManager -Path .\lcmConfig -Verbose
#Get-DscLocalConfigurationManager

### Create the MOF for the configuration
.\${dsc_outfile}

#Create a credential spec file
