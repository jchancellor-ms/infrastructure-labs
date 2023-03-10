#base template modified from bicep sample here - https://github.com/Azure/azure-quickstart-templates/blob/master/demos/imagebuilder-windowsbaseline/main.bicep
terraform {
  required_providers {
    azapi = {
      source = "azure/azapi"
    }
  }
}

variable "default_image_location" {
  type        = string
  description = "The geo-location where the image template resource lives"
  default     = "westus3"
}

variable "resource_group_id" {
  type        = string
  description = "The resource ID for the resource group holding the image template resource"
}

variable "tags" {
  type        = map(string)
  description = "List of the tags that will be assigned to each resource"
}

variable "customizer_script_uri" {
  type        = string
  description = "URI of the powershell script used for customizing."
}

variable "run_output_name" {
  type        = string
  description = "Name of the custom image to create and distribute using Azure Image Builder."
  default     = "Win2019_AzureWindowsBaseline_CustomImage"
}

variable "aib_identity_id" {
  type        = string
  description = "Azure resource Id for the aib run identity"
}

variable "replication_regions" {
  type        = list(string)
  description = "List the regions in Azure where you would like to replicate the custom image after it is created."
  default     = ["westus3", "westus2"]
}

variable "staging_resource_group_id" {
  type        = string
  description = "The resource group id for the staging resource group. Will be generated randomly if empty."
  default     = null
}

variable "shared_gallery_name" {
  type        = string
  description = "the azure resource name for the image gallery"
}

variable "rg_name" {
  type        = string
  description = "The azure resource name for the resource group"
}

variable "rg_location" {
  type        = string
  description = "Resource Group region location"
  default     = "westus2"
}

variable "deploy_subnet_id" {
  type        = string
  description = "Subnet used for the proxy VM for AIB private link connection"
}

resource "azurerm_shared_image" "image_ws2019_hardened_w_extensions" {
  name                = "Win2019_AzureWindowsBaseline_Definition"
  gallery_name        = var.shared_gallery_name
  resource_group_name = var.rg_name
  location            = var.rg_location
  os_type             = "Windows"
  hyper_v_generation  = "V1"

  identifier {
    publisher = "AzureWindowsBaseline"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
  }
}

resource "azapi_resource" "image_template_ws2019_hardened_w_extensions" {
  type      = "Microsoft.VirtualMachineImages/imageTemplates@2022-02-14"
  name      = "windows_2019_hardened_w_extensions"
  location  = var.default_image_location
  parent_id = var.resource_group_id
  tags      = var.tags
  identity {
    type         = "UserAssigned"
    identity_ids = [var.aib_identity_id]
  }
  body = jsonencode({
    properties = {
      buildTimeoutInMinutes = 60
      customize = [
        {
          name           = "WindowsUpdate"
          type           = "WindowsUpdate"
          searchCriteria = "IsInstalled=0"
          filters = [
            "exclude:$_.Title -like \"*Preview*\"",
            "include:$true"
          ]
          updateLimit = 40
        },
        {
          type        = "PowerShell"
          name        = "baseInstall"
          runElevated = true
          scriptUri   = var.customizer_script_uri
        }

      ]
      distribute = [
        {
          type               = "SharedImage"
          galleryImageId     = azurerm_shared_image.image_ws2019_hardened_w_extensions.id
          runOutputName      = var.run_output_name
          replicationRegions = var.replication_regions
        }
      ]
      source = {
        type = "PlatformImage"
        publisher : "MicrosoftWindowsServer"
        offer : "WindowsServer"
        sku : "2019-Datacenter"
        version : "latest"
      }
      stagingResourceGroup = var.staging_resource_group_id
      #TODO: build a validation block for the image build
      #validate = {
      #  continueDistributeOnFailure = bool
      #  inVMValidations = [
      #    {
      #      name = "string"
      #      type = "string"
      #      // For remaining properties, see ImageTemplateInVMValidator objects
      #    }
      #  ]
      #  sourceValidationOnly = bool
      #}
      vmProfile = {
        vmSize       = "Standard_D4as_v5"
        osDiskSizeGB = 127
        userAssignedIdentities = [
          var.aib_identity_id
        ]
        #use this section if using private IPs
        vnetConfig = {
          proxyVmSize = "Standard_D2as_v5"
          subnetId    = var.deploy_subnet_id
        }
      }
    }
  })
}

/*
resource "azurerm_resource_deployment_script_azure_power_shell" "Template_build" {
  name                = "windows_2019_hardened_w_extensions_deployment"
  resource_group_name = var.rg_name
  location            = var.rg_location
  version             = "6.2"
  retention_interval  = "P1D"
  #command_line        = "-name \"John Dole\""
  cleanup_preference = "OnSuccess"
  force_update_tag   = uuid()
  timeout            = "PT30M"

  script_content = <<EOF
          Invoke-AzResourceAction -ResourceName "${azapi_resource.image_template_ws2019_hardened_w_extensions.name}" -ResourceGroupName "${var.rg_name}" -ResourceType "Microsoft.VirtualMachineImages/imageTemplates" -ApiVersion "2020-02-14" -Action Run -Force
  EOF

  identity {
    type = "UserAssigned"
    identity_ids = [
      var.aib_identity_id
    ]
  }

  tags = var.tags
}
*/