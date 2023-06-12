#Set strict mode
set-strictmode -version latest

# enumerate all the public and private functions in the module
$Public = @(Get-ChildItem -Path $PSScriptRoot/public/*.ps1 -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path $PSScriptRoot/private/*.ps1 -ErrorAction SilentlyContinue)

# Import all of the public and private functions by dot sourcing them
foreach ($import in @($Public + $Private)) {
    try {
        Write-Verbose "Importing $($import.FullName)"
        . $import.FullName
    } catch {
        Write-Error "Failed to import function $($import.FullName): $_"
    }
}

# Export all of the public functions
foreach ($file in $Public) {
    Export-ModuleMember -Function $file.BaseName
}