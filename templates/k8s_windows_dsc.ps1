Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module CredentialSpec -Force

Configuration k8s {
    #########################################################################
    # Import the DSC modules used in the configuration
    ########################################################################
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DSCResource -Name WindowsFeature  

    Node localhost
    {
        #Add the containers and hypervisor features and reboot if needed 
        WindowsFeature 'Containers'
        {
            Name                 = 'Containers'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        WindowsFeature 'Hyper-v'
        {
            Name                 = 'Hyper-v'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        WindowsFeature 'Hyper-v-powershell'
        {
            Name                 = 'Hyper-v'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        #Install containerd
        script 'installContainerd' {
            GetScript            = { return @{result = 'Installing Containerd' } }
            TestScript           = { 
                #check to see if the containerd service exists
                #Future versions of this may need to validate specific service configurations

                if (!(Get-Service containerd -erroraction SilentlyContinue)) { 
                    $return = $false 
                }
                else
                {
                    $return = $true
                }
                
                return $return 
            }
            SetScript            = {                    
                #move to the temp directory
                New-Item -Path 'c:\temp' -ItemType Directory -ErrorAction SilentlyContinue
                set-location -Path 'c:\temp'
                #get the latest release version number for use in the download
                $latest = ((Invoke-WebRequest -Uri https://api.github.com/repos/containerd/containerd/releases/latest).content | convertfrom-json).tag_name
                $latestnum = $latest.substring(1)
                #download and extract the installation files
                curl.exe -L https://github.com/containerd/containerd/releases/download/$latest/containerd-$latestnum-windows-amd64.tar.gz -o containerd-windows-amd64.tar.gz
                tar.exe xvf .\containerd-windows-amd64.tar.gz
                Copy-Item -Path ".\bin\" -Destination "$Env:ProgramFiles\containerd" -Recurse -Force
                #configure and start the containerd service
                cd $Env:ProgramFiles\containerd\
                .\containerd.exe config default | Out-File config.toml -Encoding ascii
                .\containerd.exe --register-service
                Start-Service containerd
            }
        }

        script 'configureAKVGmsaCcgPlugin' {
            GetScript            = { return @{result = 'Installing GMSA CCG Plugin' } }
            TestScript           = { 
                #check to see if the new reg key exists
                if ((Get-ChildItem -Path 'HKLM:\SOFTWARE\CLASSES\CLSID\{CCC2A336-D7F3-4818-A213-272B7924213E}' -ErrorAction SilentlyContinue).count -ne 2) { 
                    $return = $false 
                }
                else
                {
                    $return = $true
                }
                
                return $return 
            }
            SetScript            = {                    
                #Patterned after file found here - https://github.com/kubernetes-sigs/image-builder/blob/master/images/capi/ansible/windows/roles/gmsa/tasks/gmsa_keyvault.yml
                #move to the temp directory
                New-Item -Path 'c:\temp' -ItemType Directory -ErrorAction SilentlyContinue
                set-location -Path 'c:\temp'
                #consider putting a version of this locally in the repository to avoid location/version drift
                curl.exe -L https://kubernetesartifacts.azureedge.net/ccgakvplugin/v1.1.4/binaries/windows-gmsa-ccgakvplugin-v1.1.4.zip -o windows-gmsa-ccgakvplugin.zip
                Expand-Archive -LiteralPath .\windows-gmsa-ccgakvplugin.zip -DestinationPath .\gmsa

                #copy keyvault plugin to system32
                set-location -path 'c:\temp\gmsa'
                Move-Item -Force -Path .\CCGAKVPlugin.dll -Destination "$ENV:Systemroot\system32\"
                #Register the key vault CCG plugin                
                .\install-gmsa-keyvault-plugin.ps1
                #Install the logging manifests
                wevtutil.exe um .\CCGEvents.man
                wevtutil.exe im .\CCGEvents.man
                wevtutil.exe um .\CCGAKVPluginEvents.man
                wevtutil.exe im .\CCGAKVPluginEvents.man

            }
        }
    }
}

k8s
Start-dscConfiguration -Path ./k8s -Force