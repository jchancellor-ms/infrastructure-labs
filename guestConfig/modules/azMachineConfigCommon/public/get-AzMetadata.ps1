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