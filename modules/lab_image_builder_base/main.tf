#Create a user assigned managed identity for use by Azure Image Builder
resource "azurerm_user_assigned_identity" "AIB_Identity" {
  location            = var.rg_location
  name                = var.aib_identity_name
  resource_group_name = var.rg_name
}


#create custom role for AIB template and deployment script
resource "azurerm_role_definition" "AIB_Role" {
  name        = var.aib_role_name
  scope       = var.aib_role_scope
  description = "Used for AIB template and ARM deployment script that runs AIB build"

  permissions {
    actions = [
      "Microsoft.Compute/galleries/read",
      "Microsoft.Compute/galleries/images/read",
      "Microsoft.Compute/galleries/images/versions/read",
      "Microsoft.Compute/galleries/images/versions/write",
      "Microsoft.Compute/images/read",
      "Microsoft.Compute/images/write",
      "Microsoft.Compute/images/delete",
      "Microsoft.Storage/storageAccounts/blobServices/containers/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/write",
      "Microsoft.ContainerInstance/containerGroups/read",
      "Microsoft.ContainerInstance/containerGroups/write",
      "Microsoft.ContainerInstance/containerGroups/start/action",
      "Microsoft.Resources/deployments/read",
      "Microsoft.Resources/deploymentScripts/read",
      "Microsoft.Resources/deploymentScripts/write",
      "Microsoft.VirtualMachineImages/imageTemplates/run/action",
    ]
    not_actions = []
  }
}

#assign the AIB role to the AIB identity 
resource "azurerm_role_assignment" "AIB_role_assignment" {
  scope                = var.aib_role_scope
  role_definition_name = azurerm_role_definition.AIB_Role.name
  principal_id         = azurerm_user_assigned_identity.AIB_Identity.principal_id
}

resource "azurerm_shared_image_gallery" "AIB_image_gallery" {
  #add a for_each to create multiple galleries
  name                = var.image_gallery_name
  resource_group_name = var.rg_name
  location            = var.rg_location
  description         = "Azure Image Builder Shared Gallery"

  tags = var.tags
}

