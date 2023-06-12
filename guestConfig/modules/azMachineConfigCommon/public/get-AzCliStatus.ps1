#determine whether the CLI is currently installed and what version
function Get-AzCliStatus {     
    $azCommand = 'sudo az -v | sudo grep azure-cli'

        #set an initial set of default values
        $cliData = @{
            installStatus = "Unknown"
            version = $null
            versionStatus = "Unknown"
            error = $null
        }

        #run the version command for the cli
        try {
            $message = $(Invoke-Command -ScriptBlock { bash -c $azCommand })
        }
        catch {
            $message = $null
            $cliData = @{
                installStatus = "NotInstalled"
                version = $null
                error = $_
            }
            Write-Error -Message "Failed to get CLI version with error : $_"
        }

        #determine the current state of the cli install
        if ($message){
            if ($message.split(" ")[0] -eq 'azure-cli' -and $message.split(" ")[-1] -eq "*"){
                $cliData = @{
                    installStatus = "Installed"
                    versionStatus = "UpgradeAvailable"
                    version = $message.split(" ")[-2]
                }
                
            }
            elseif ($message.split(" ")[0] -eq 'azure-cli' -and $message.split(" ")[-1] -ne "*"){
                $cliData = @{
                    installStatus = "Installed"
                    versionStatus = "Latest"
                    version = $message.split(" ")[-1]
                }
            }
            else {
                $cliData = @{
                    installStatus = "Unknown"
                    versionStatus = "Unknown"
                    version = $message.split(" ")[-1]
                }
            }
        }

    return $cliData
}

