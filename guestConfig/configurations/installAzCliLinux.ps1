param(
    [string[]]$outDirectory = "./compiledConfigurations"
)

$outFullPath = "$outDirectory/installAzCliLinux"

If (!(Test-Path -PathType container $outFullPath)) {
    New-Item -ItemType Directory -Path $outFullPath
}

Configuration installAzCliLinux {
    Import-DscResource -Name 'installAzCliLinux' -ModuleName 'installAzCliLinux'
    installAzCliLinux thisLinuxMachine {
        name = "AzCLILatest"
        ensure = "Present"
    }
}

InstallAzCliLinux -out $outFullPath