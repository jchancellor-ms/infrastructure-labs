[DscResource()]
class installAzCliLinux {
    [DscProperty(Key)]
    [string] $Name

    [DscProperty(Mandatory)]
    [installAzCliLinuxEnsure] $Ensure

    [DscProperty(NotConfigurable)]
    [installAzCliReason[]] $Reasons = [installAzCliReason[]]::new()

    [DscProperty()]
    [String] $Version

    [DscProperty()]
    [String] $versionStatus


    # class constructor
    # Get() method
    [installAzCliLinux] Get() {
    
        # Create the constructor
        $currentState = [installAzCliLinux]::new()
        $CurrentState.Name = $this.Name

        #get the data from the metadata
        $metadata = $this.getVmDetails()
        $cliStatus = Get-AzCliStatus
        

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

#define a class resource for the Reason property
class installAzCliReason {
    [DscProperty()]
    [string] $Code

    [DscProperty()]
    [string] $Phrase
}


#define a class resource for the cliStatus property
class installAzCliStatus {
    [DscProperty()]
    [string] $installStatus

    [DscProperty()]
    [string] $version

    [DscProperty()]
    [string] $versionStatus

    [DscProperty()]
    [string] $error
}

