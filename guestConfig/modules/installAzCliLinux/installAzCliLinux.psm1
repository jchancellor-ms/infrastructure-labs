[DscResource()]
class installAzCliLinux {
    [DscProperty(Key)]
    [string] $name

    [DscProperty(Mandatory)]
    [installAzCliLinuxEnsure] $ensure

    [DscProperty(NotConfigurable)]
    [installAzCliReason[]] $reasons

    [DscProperty()]
    [String] $version = $null

    [DscProperty()]
    [String] $versionStatus = $null


    # class constructor
    # Get() method
    [installAzCliLinux] Get() {        

        # Create the constructor
        $currentState = [installAzCliLinux]::new()
        $currentState.name = $this.name

        $metadata = get-AzMetadata
        $cliStatus = get-AzCliStatus

        #get the data from the metadata        

        if ($cliStatus.installStatus -eq "NotInstalled" -and $metadata.compute.osType -eq "Linux") {
            $currentState.ensure = [installAzCliLinuxEnsure]::Absent
            $currentState.version = $null
            $currentState.versionStatus = $null
            
            $currentState.reasons += [installAzCliReason[]]@{
                Code = "$($this.name):AzureCLI:NotInstalled"
                Phrase = "The Azure CLI is not currently installed."
            } 
        }
        elseif ($cliStatus.installStatus -eq "Unknown" -and $metadata.compute.osType -eq "Linux") {
            $currentState.ensure = [installAzCliLinuxEnsure]::Absent
            $currentState.version = $null
            $currentState.versionStatus = $null
            $currentState.reasons += [installAzCliReason[]]@{
                Code = "$($this.name):AzureCLI:Unknown"
                Phrase = "The Azure CLI installation status was unable to be determined and returned error $($cliStatus.error)"
            }             
        }
        else {
            $currentState.ensure = [installAzCliLinuxEnsure]::Present
            $currentState.version = $cliStatus.version
            $currentState.versionStatus = $cliStatus.versionStatus
            if ($cliStatus.versionStatus -eq "UpgradeAvailable") {
                $currentState.reasons += [installAzCliReason[]]@{
                    Code = "$($this.name):AzureCLI:UpgradeAvailable"
                    Phrase = "The Azure CLI is installed but a newer version is available for upgrade"
                }      
            }
            else {
                $currentState.reasons += [installAzCliReason[]]@{
                    Code = "$($this.name):AzureCLI:Latest"
                    Phrase = "The Azure CLI is installed and at the latest version"
                }  
            }
        }

        return $currentState
    }

    [bool] Test() {
        # Test the current state of the resource against the desired state
        $currentState = $this.Get()

        # if current state of Ensure does not match what I specified in my manifest
        if ($currentState.ensure -ne $this.ensure) {
            return $false
        }

        if ($currentState.versionStatus -ne "Latest"){
            return $false
        }

        # if neither of these conditions are met then it is in state (i.e. compliant)
        return $true
    }

    [void] Set() {

        #Use the test method to validate whether the vm is in the proper state
        if ($this.Test()) {
            return
        }

        #if test failed, run the install
        $curlCommand = "sudo apt-get update;sudo apt-get install azure-cli -y"
        Invoke-Command -ScriptBlock { bash -c $curlCommand }

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

