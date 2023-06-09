#!/bin/bash

#install the cli if not currently installed
az -v &> /dev/null
if [ $? -ne 0 ]
  then
    echo "Azure CLI not installed"
    sudo apt-get install ca-certificates curl apt-transport-https lsb-release gnupg -y
    sudo mkdir -p /etc/apt/keyrings
    curl -sLS https://packages.microsoft.com/keys/microsoft.asc |
        gpg --dearmor |
        sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
    AZ_REPO=$(lsb_release -cs)
    echo "deb [arch=`dpkg --print-architecture` signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" |
        sudo tee /etc/apt/sources.list.d/azure-cli.list
    sudo apt-get update
    sudo apt-get install azure-cli -y
  else
    echo "installed"
fi

jq --help &> /dev/null
if [ $? -ne 0 ]
  then 
    echo "jq not installed"
    sudo apt install jq -y
  else
    echo "jq is installed"
fi

#install the AMA agent if not currently installed
RESOURCEID=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | jq -r '.compute.resourceId')
RESOURCEGROUPNAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | jq -r '.compute.resourceGroupName')
VMNAME=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | jq -r '.compute.name')
#check to see if extension is currently installed
AMASTATE=$(az vm extension show --name AzureMonitorLinuxAgent --resource-group $RESOURCEGROUPNAME --vm-name $VMNAME | jq -r '.provisioningState')

if [ "$AMASTATE" == "Succeeded" ]
  then 
    echo "Azure AMA agent extension installed"
  else
    echo "Azure AMA agent extension not installed"
    az vm extension set --name AzureMonitorLinuxAgent --publisher Microsoft.Azure.Monitor --ids $RESOURCEID --enable-auto-upgrade true
fi
    
