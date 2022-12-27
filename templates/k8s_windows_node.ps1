#create a working folder
New-Item -Path 'c:\temp' -ItemType Directory
set-location -Path 'c:\temp'

install-windowsfeature -name containers
install-windowsfeature -name hyper-v
install-windowsfeature -name hyper-v-powershell


#Install and configure containerd move this to a post reboot script via runcmd
$latest = ((Invoke-WebRequest -Uri https://api.github.com/repos/containerd/containerd/releases/latest).content | convertfrom-json).tag_name
$latestnum = $latest.substring(1)
curl.exe -L https://github.com/containerd/containerd/releases/download/$latest/containerd-$latestnum-windows-amd64.tar.gz -o containerd-windows-amd64.tar.gz
tar.exe xvf .\containerd-windows-amd64.tar.gz
Copy-Item -Path ".\bin\" -Destination "$Env:ProgramFiles\containerd" -Recurse -Force
cd $Env:ProgramFiles\containerd\
.\containerd.exe config default | Out-File config.toml -Encoding ascii
.\containerd.exe --register-service
Start-Service containerd

set-location -Path 'c:\temp'


#install and configure the GMSA CCG plugin
#download the plugin artifacts (don't know where this file gets generated typically)
curl.exe -L https://kubernetesartifacts.azureedge.net/ccgakvplugin/v1.1.4/binaries/windows-gmsa-ccgakvplugin-v1.1.4.zip -o windows-gmsa-ccgakvplugin.zip
Expand-Archive -LiteralPath .\windows-gmsa-ccgakvplugin.zip -DestinationPath .\gmsa

set-location -path 'c:\temp\gmsa'
Invoke-webRequest -Uri https://raw.githubusercontent.com/kubernetes-sigs/image-builder/master/images/capi/ansible/windows/roles/gmsa/files/install-gmsa-keyvault-plugin.ps1 -outfile .\install-gmsa-keyvault-plugin.ps1

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module CredentialSpec -Force

