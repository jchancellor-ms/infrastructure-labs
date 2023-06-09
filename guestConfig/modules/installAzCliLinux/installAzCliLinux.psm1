[DscResource()]
class installAzCliLinux {
    [DscProperty(Key)]
    [string] $Name

    [DscProperty(Mandatory)]
    [installAzCliLinuxEnsure] $Ensure

    [DscProperty(NotConfigurable)]
    [installAzCliReason[]] $Reasons


    # class constructor
    # Get() method
    [installAzCliLinux] Get() {

        #get the data from the metadata
        $metadata = Get-VmDetails
        $cliStatus = Get-AzCliStatus


        # Get the current state of the resource
        $currentState = [installAzCliLinux]::new()

        if ($cliStatus.installStatus -eq "NotInstalled" -and $metadata.compute.osType -eq "Linux") {
            $currentState.Ensure = [installAzCliLinuxEnsure]::Absent
            $currentState.version = $null
            $currentState.versionStatus = $null
            $currentState.Reasons += "The Azure CLI is not currently installed."
        }
        elseif ($cliStatus.installStatus -eq "Unknown" -and $metadata.compute.osType -eq "Linux") {
            $currentState.Ensure = [installAzCliLinuxEnsure]::Absent
            $currentState.version = $null
            $currentState.versionStatus = $null
            $currentState.Reasons += "The Azure CLI installation status was unable to be determined and returned error $($cliStatus.error)"
        }
        else {
            $currentState.Ensure = [installAzCliLinuxEnsure]::Present
            $currentState.version = $cliStatus.version
            $currentState.versionStatus = $cliStatus.versionStatus
            if ($cliStatus.versionStatus -eq "UpgradeAvailable") {
                $currentState.Reasons += "The Azure CLI is installed but a newer version is available for upgrade"
            }
            else {
                $currentState.Reasons += "The Azure CLI is installed and at the latest version"
            }
        }

        return $currentState
    }

    [bool] Test() {
        # Test the current state of the resource against the desired state
        $CurrentState = $this.Get()

        # if current state of Ensure does not match what I specified in my manifest
        if ($CurrentState.Ensure -ne $this.Ensure) {
            return $false
        }

        if ($CurrentState.versionStatus -ne "Latest"){
            return $false
        }

        # if neither of these conditions are met then it is in state (i.e. compliant)
        return $true
    }

    [void] Set() {

        # Set always calls test first, test calls get (Current design pattern)
        # this enables avoid side effects - if test was not run, you would note have a guarantee that the configuration is wrong
        # only take action if you have to

        # if this is true, then do nothing (because it is already in the desired state)
        # No need to use further compute resources
        # if it returns false we know that we can proceed with SET safely 
        if ($this.Test()) {
            return
        }

        #if test failed, run the az CLI version agnostic install script
        $installCommand = "sudo curl -L https://aka.ms/InstallAzureCli | sudo bash"
        $installOutput = Invoke-Command -ScriptBlock { bash -c $curlCommand }

    }
}

enum installAzCliLinuxEnsure
{
    Absent
    Present
}

class installAzCliReason {
    [DscProperty()]
    [string] $Code

    [DscProperty()]
    [string] $Phrase
}

#get data from the IMDS for the vm for use in decision making
function Get-VmDetails{

    $curlCommand = 'sudo curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01"' 
    try {
        $metadata = ConvertFrom-Json -inputObject $(Invoke-Command -ScriptBlock { bash -c $curlCommand })
    }
    catch {
        Write-Error -Message "Failed to get VM metadata from Instance Metadata Service with error : $_"
    }

    return $metadata

}

#determine whether the CLI is currently installed and what version
function Get-AzCliStatus {

    $azCommand = 'sudo az -v | sudo grep azure-cli'

    try {
        $message = ConvertFrom-Json -inputObject $(Invoke-Command -ScriptBlock { bash -c $azCommand })
    }
    catch {
        $message = $null
        $cliData.installStatus = "NotInstalled"
        $cliData.version = $null
        $cliData.error = $_
        Write-Error -Message "Failed to get CLI version with error : $_"
    }

    if ($message){
        if ($message.split(" ")[0] -eq 'azure-cli' -and $message.split(" ")[-1] -eq "*"){
            $cliData.installStatus = "Installed"
            $cliData.versionStatus = "UpgradeAvailable"
            $cliData.version = $message.split(" ")[-2]
        }
        elseif ($message.split(" ")[0] -eq 'azure-cli' -and $message.split(" ")[-1] -ne "*"){
            $cliData.installStatus = "Installed"
            $cliData.versionStatus = "Latest"
            $cliData.version = $message.split(" ")[-1]
        }
        else {
            $cliData.installStatus = "Unknown"
            $cliData.versionStatus = "Unknown"
            $cliData.version = $message.split(" ")[-1]
        }
    }

    return $cliData
}
