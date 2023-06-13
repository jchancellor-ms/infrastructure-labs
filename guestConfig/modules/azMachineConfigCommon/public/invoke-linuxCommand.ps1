
function invoke-LinuxCommand{

    

    $message = $(Invoke-Command -ScriptBlock { 
        try {
            bash -c $azCommand 2>&1
        }
        catch {
            return $null
        }
    } -ErrorAction SilentlyContinue )

}

