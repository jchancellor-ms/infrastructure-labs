[DscResource()]
class emptyModule {
    [DscProperty(Key)]
    [string] $name

    [DscProperty(Mandatory)]
    [emptyModuleEnsure] $ensure

    [DscProperty(NotConfigurable)]
    [installAzCliReason[]] $reasons


    # class constructor
    # Get() method
    [emptyModule] Get() {        

        # Create the constructor
        $currentState = [emptyModule]::new()
        $currentState.name = $this.name
        $currentState.ensure = $this.ensure
        $currentState.reasons += [installAzCliReason[]]@{
            Code = "$($this.name):emptyModule:NotInstalled"
            Phrase = "This is an empty module for testing."
        } 

        return $currentState
    }

    [bool] Test() {
        # Test the current state of the resource against the desired state
        $currentState = $this.Get()

        return $false
    }

    [void] Set() {
        if ($this.Get()) {
            return
        }

        Write-Output "This is a test output"
        Write-Host "This is a test screen output"

    }
       
}

enum emptyModuleEnsure
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

