#base template modified from bicep sample here - https://github.com/Azure/azure-quickstart-templates/blob/master/demos/imagebuilder-windowsbaseline/main.bicep
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

variable "user_assigned_identity_id" {
  type        = list(string)
  description = "list of user identities associated with the image template"
}

variable "customizer_script_uri" {
  type        = string
  description = "URI of the powershell script used for customizing."
}

variable "image_definition_id" {
  type        = string
  description = "The gallery image ID for the shared image"
}

variable "run_output_name" {
  type        = string
  description = "Name of the custom image to create and distribute using Azure Image Builder."
}

variable "replication_regions" {
  type        = list(string)
  description = "List the regions in Azure where you would like to replicate the custom image after it is created."
}

variable "staging_resource_group_id" {
  type        = string
  description = "The resource group id for the staging resource group. Will be generated randomly if empty."
  default     = null
}

resource "azapi_resource" "image_ws2019_hardened_w_extensions" {
  type      = "Microsoft.VirtualMachineImages/imageTemplates@2022-02-14"
  name      = "windows_2019_hardened_w_extensions"
  location  = var.default_image_location
  parent_id = var.resource_group_id
  tags      = var.tags
  identity {
    type         = "UserAssigned"
    identity_ids = var.user_assigned_identity_id
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
          name        = "AzureWindowsBaseline"
          runElevated = true
          scriptUri   = var.customizer_script_uri
        }
      ]
      distribute = [
        {
          type               = "SharedImage"
          galleryImageId     = var.image_definition_id
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
      stagingResourceGroup = var.staging_resource_group
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
        vmSize       = "Standard_D2_v3"
        osDiskSizeGB = 127
        userAssignedIdentities = [
          "string"
        ]
        #use this section if using private IPs
        #vnetConfig = {
        #  proxyVmSize = "string"
        #  subnetId = "string"
        #}
      }
    }
  })
}