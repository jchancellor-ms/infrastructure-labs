{
    "properties": {
        "buildTimeoutInMinutes": 80,
        "vmProfile": {
            "vmSize"       : "Standard_D4as_v5",
            "osDiskSizeGB" : 127,
            "userAssignedIdentities" : [
                "${aib_identity_id}"
            ],
            "vnetConfig" : {
                "proxyVmSize" : "Standard_D2as_v5",
                "subnetId"    : "${deploy_subnet_id}"
            }            
        },
        "source": {
            "type": "PlatformImage",
            "publisher": "Canonical",
            "offer": "UbuntuServer",
            "sku": "18.04-LTS",
            "version": "latest"
        },
        "stagingResourceGroup" : "${staging_resource_group_id}",
        "customize": [
            {
                "type": "Shell",
                "name": "Install the Azure CLI as a test app",
                "inline": [
                    "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
                ]
            },
            {
                "type": "Shell",
                "name": "InstallUpgrades",
                "inline": [
                    "sudo apt install unattended-upgrades"
                ]
            },
            {
                "type": "Shell",
                "name": "Replace /etc/machine-id with empty file to ensure UA client does not see clones as duplicates",
                "inline": [
                    "sudo rm -f /etc/machine-id && sudo touch /etc/machine-id"
                ]
            }
        ],
        "distribute": [
            {
                "type": "SharedImage",
                "galleryImageId": "${gallery_image_id}",
                "runOutputName": "${run_output_name}",
                "artifactTags": {
                    "source": "azVmImageBuilder",
                    "baseosimg": "ubuntu1804"
                },
                "replicationRegions": ${replication_regions}
            }
        ]
    }
}