Param
(
    [Parameter(
        Mandatory=$true,
        HelpMessage="Provide the directory path where the working content resides.")]
    [String]
    $contentPath=".",
    $buildVersion = "0.0.1",
    $type = "AuditAndSet"

)




#install the required powershell modules for creating the configuration
Install-Module -Name PSDesiredStateConfiguration -MinimumVersion 2.0.6 -AcceptLicense -SkipPublisherCheck -Repository PSGallery -Force
Import-Module PSDesiredStateConfiguration -Force -MinimumVersion 2.0.6
Install-Module -Name GuestConfiguration -MinimumVersion 4.3.0 -AcceptLicense -SkipPublisherCheck -Repository PSGallery -Force          

# This module is required for all machine config modules
Import-Module "$contentPath/modules/AzMachineConfigCommon/AzMachineConfigCommon.psd1" -force

#copy the modules path to the default modules path on the build machine
copy-item -path "$contentPath/modules/*" -Destination "/usr/local/share/powershell/Modules" -Recurse -Force



#import the modules on the build machine
$modules = Get-ChildItem "$contentPath/modules/" -Directory
foreach ($module in $modules){
    $manifestPath = Join-Path -Path $module.FullName -ChildPath ($module.Name + ".psd1")
    
    $Params = @{
        Path = $manifestPath
        ModuleVersion = $buildVersion
    }
    
    #update the common modules manifest functions params
    if ($module.Name -eq "AzMachineConfigCommon") {

        # Enumerate all public functions
        $publicFunctionPath = Join-Path -Path $module.FullName -ChildPath "Public"
        $publicFunctions = Get-ChildItem $publicFunctionPath | ForEach-Object { $_.BaseName }
        $Params += @{FunctionsToExport = $publicFunctions}
        Update-ModuleManifest @Params
    }
    import-module $module.Name -force
}

#build each configuration
$configurations = Get-ChildItem "$contentPath/configurations/" -Recurse -Filter *.ps1
foreach ($configuration in $configurations)
{
    #compile the configuration 
    . $configuration.FullName

    #rename the compiled configuration 
    Rename-Item -Path "./compiledConfigurations/$($configuration.BaseName)/localhost.mof" -NewName "$($configuration.BaseName).mof" -PassThru

    #create the package
    $compiledConfiguration = "$contentPath/compiledConfigurations/$($configuration.BaseName)/$($configuration.BaseName).mof"

    new-GuestConfigurationPackage -Name  $configuration.BaseName -Configuration $compiledConfiguration -Path $contentPath/packages/ -FilesToInclude "$contentPath/modules/AzMachineConfigCommon/" -Version $buildVersion -Type $type -Force  
}