Configuration k8s {
    #########################################################################
    # Import the DSC modules used in the configuration
    ########################################################################
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName DnsServerDsc
    Import-DscResource -ModuleName SecurityPolicyDsc
    Import-DscResource -ModuleName ComputerManagementDsc
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
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Adding Admin User to SQL sysadmin role for DB creation' } }
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
}