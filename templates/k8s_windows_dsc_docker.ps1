#create the temp directory
New-Item -Path 'c:\temp' -ItemType Directory -ErrorAction SilentlyContinue
set-location -Path 'c:\temp'

$cert = Get-ChildItem -Path cert:\LocalMachine\My\${dsc_cert_thumbprint}
Export-Certificate -Cert $cert -FilePath .\dsc.cer
certutil -encode dsc.cer dsc64.cer

[DSCLocalConfigurationManager()]
Configuration lcmConfig {
    Node localhost
    {
        Settings
        {
            RefreshMode = 'Push'
            ActionAfterReboot = "ContinueConfiguration"
            RebootNodeIfNeeded = $true
            ConfigurationModeFrequencyMins = 15
            CertificateID = "${dsc_cert_thumbprint}"
        }
    }
}

Write-Host "Creating LCM mof"
lcmConfig -InstanceName localhost -OutputPath .\lcmConfig
Set-DscLocalConfigurationManager -Path .\lcmConfig -Verbose

#build the dsc configuration
Configuration k8s {
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


        #Install Docker
        script 'installDocker' {
            GetScript            = { return @{result = 'Installing Docker' } }
            TestScript           = { 
                #check to see if the docker service is responding
                
                return (Test-Path "//./pipe/docker_engine")
            }
            SetScript            = {                    
                Install-Package -Name docker -ProviderName DockerMsftProvider -Force
                Start-Service Docker
                Restart-Computer -Force
                
            }
        }       

        #Install cri-dockerd (to allow for kubernetes to work)
        script 'installCriDockerd' {
            DependsOn            = "[script]installDocker"
            GetScript            = { return @{result = 'Installing cri-dockerd' } }
            TestScript           = { 
                #check to see if the cri-dockerd service exists
                if (get-service cri-dockerd -errorAction SilentlyContinue) {
                    $return = $true
                }
                else {
                    $return = $false
                }
                return $return
            }
            SetScript            = {                    
                #InstallNssm
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
                New-Item -Path 'c:\temp\cri-dockerd' -ItemType Directory -ErrorAction SilentlyContinue
                set-location -Path 'c:\temp\cri-dockerd'                
                Invoke-WebRequest -Uri https://github.com/Mirantis/cri-dockerd/releases/download/v0.2.0/cri-dockerd-v0.2.0-windows-amd64.zip -UseBasicParsing -o cri-dockerd.zip
                Expand-Archive -LiteralPath cri-dockerd.zip -DestinationPath . -Force
                tar xvf cri-dockerd-v0.2.0-linux-amd64.tar.gz                
                Move-Item -Path cri-dockerd.exe -Destination C:\Windows\System32
                Invoke-WebRequest -Uri https://k8stestinfrabinaries.blob.core.windows.net/nssm-mirror/nssm-2.24.zip -UseBasicParsing -o nssm.zip
                tar xvf .\nssm.zip --strip-components 2 */win64/*.exe
                .\nssm.exe install cri-dockerd "c:\windows\system32\cri-dockerd.exe"
                .\nssm.exe start cri-dockerd                
            }
        } 

        #Configure Node using Calico teams scripts
        script 'joinToKubernetes' {
            DependsOn            = "[script]installCriDockerd"
            GetScript            = { return @{result = 'Joining to kubernetes' } }
            TestScript           = { 
                if (get-service -Name kubelet -errorAction SilentlyContinue) {
                    $return = $true
                }
                else {
                    $return = $false
                }
                #return $true  #stops run for now, check service statuses?
                return $return
            }        
            SetScript            = {
                New-Item -Path 'c:\k' -ItemType Directory -ErrorAction SilentlyContinue
                set-location -Path 'c:\k'
                Connect-AzAccount -Identity | Out-Null
                Get-AzKeyVaultSecret -vaultName ${vault_name} -Name ${conf_secret_name} -AsPlainText >> config
                $certHash = Get-AzKeyVaultSecret -vaultName ${vault_name} -Name ${hash_name} -AsPlainText 
                $k8sVersion = Get-AzKeyVaultSecret -vaultName ${vault_name} -Name ${version_name} -AsPlainText 
                #Use the Calico created install script to configure the CNI
                Invoke-WebRequest https://projectcalico.docs.tigera.io/scripts/install-calico-windows.ps1 -OutFile c:\install-calico-windows.ps1
                #fix an issue where the findstr doesn't get the server info from the config
                $findString = 'findstr https:// $KubeConfigPath'
                $replaceString = '(Get-Content $KubeConfigPath | Select-String -Pattern "https://" )[0].ToString().Trim()'
                ((Get-Content -path c:\install-calico-windows.ps1 -Raw) -replace [Regex]::Escape($findString), $replaceString) | set-content -path c:\install-calico-windows.ps1
                #run the install script with the version and defaults
                
                C:\install-calico-windows.ps1 -KubeVersion $k8sVersion.split("v")[1].trim('"') -ServiceCidr 10.96.0.0/12 -DNSServerIPs 10.96.0.10                
                C:\CalicoWindows\kubernetes\install-kube-services.ps1                
                #modify c:\CalicoWindows\kubernetes\kubelet-service.ps1 to remove the deprecated logtostderr parameter that causes the service to bounce
                $kubeletPath = "c:\CalicoWindows\kubernetes\kubelet-service.ps1"
                (Get-Content $kubeletPath | Where-Object { $_ -notmatch 'logtostderr' }) | Set-Content $kubeletPath
                Start-Service -Name kubelet
                Start-Service -Name kube-proxy
                #join the cluster
                kubeadm join ${control_node_ip}:6443 --token ${node_token_value} --discovery-token-ca-cert-hash sha256:$certHash
            }
        }


        script 'configureAKVGmsaCcgPlugin' {
            DependsOn            = "[script]joinToKubernetes"
            GetScript            = { return @{result = 'Installing GMSA CCG Plugin' } }
            TestScript           = { 
                #check to see if the new reg key exists
                if ((Get-ChildItem -Path 'HKLM:\SOFTWARE\CLASSES\CLSID\{CCC2A336-D7F3-4818-A213-272B7924213E}' -ErrorAction SilentlyContinue).valuecount -ne 2) { 
                    $return = $false 
                }
                else {
                    $return = $true
                }
                
                return $return 
                #return $true
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
                Invoke-webRequest -Uri https://raw.githubusercontent.com/kubernetes-sigs/image-builder/master/images/capi/ansible/windows/roles/gmsa/files/install-gmsa-keyvault-plugin.ps1 -outfile .\install-gmsa-keyvault-plugin.ps1
                #Register the key vault CCG plugin                
                c:\temp\gmsa\install-gmsa-keyvault-plugin.ps1
                #Install the logging manifests
                wevtutil.exe um .\CCGEvents.man
                wevtutil.exe im .\CCGEvents.man
                wevtutil.exe um .\CCGAKVPluginEvents.man
                wevtutil.exe im .\CCGAKVPluginEvents.man

            }
        }
    }
}

$cd = @{
    AllNodes = @(    
        @{ 
            NodeName        = "localhost"
            CertificateFile = "C:\temp\dsc64.cer"
            Thumbprint      = "${dsc_cert_thumbprint}"
        }
    ) 
}

#build the MOF
k8s -ConfigurationData $cd

#run the DSC configuration
Start-dscConfiguration -Path ./k8s -Force