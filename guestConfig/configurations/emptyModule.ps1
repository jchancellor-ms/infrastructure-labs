param(
    [string[]]$outDirectory = "./compiledConfigurations"
)

$outFullPath = "$outDirectory/emptyModule"

If (!(Test-Path -PathType container $outFullPath)) {
    New-Item -ItemType Directory -Path $outFullPath
}

Configuration emptyModule {
    Import-DscResource -ModuleName emptyModule

    Node localhost{
        emptyModule thisLinuxMachine {
            name = "emptyModule"
            ensure = "Present"
        }
    }        
}

emptyModule -out $outFullPath