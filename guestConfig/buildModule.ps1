Param
(
    [Parameter(
        Mandatory=$true,
        HelpMessage="Provide the directory path where the working content resides.")]
    [String]
    $contentPath=".",
    $version = "0.0.1",
    $type = "AuditAndSet"

)

#install the required powershell modules for creating the configuration
Install-Module -Name PSDesiredStateConfiguration -MinimumVersion 2.0.6 -AcceptLicense -SkipPublisherCheck -Repository PSGallery -Force
Import-Module PSDesiredStateConfiguration -Force -MinimumVersion 2.0.6
Install-Module -Name GuestConfiguration -MinimumVersion 4.3.0 -AcceptLicense -SkipPublisherCheck -Repository PSGallery -Force          


#copy the modules path to the default modules path
copy-item -path "$contentPath/modules/*" -Destination "/usr/local/share/powershell/Modules" -Recurse -Force

$modules = Get-ChildItem "$contentPath/modules/" -Directory
foreach ($module in $modules){
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

    new-GuestConfigurationPackage -Name  $configuration.BaseName -Configuration $compiledConfiguration -Path $contentPath/packages/ -Version $version -Type $type -Force  
}