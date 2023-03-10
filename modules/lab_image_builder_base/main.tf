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
      "Microsoft.Storage/storageAccounts/blobServices/containers/delete",
      "Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action",
      "Microsoft.ContainerInstance/containerGroups/read",
      "Microsoft.ContainerInstance/containerGroups/write",
      "Microsoft.ContainerInstance/containerGroups/start/action",
      "Microsoft.Resources/deployments/read",
      "Microsoft.Resources/deploymentScripts/read",
      "Microsoft.Resources/deploymentScripts/write",
      "Microsoft.VirtualMachineImages/imageTemplates/run/action",
      "Microsoft.Network/virtualNetworks/read",
      "Microsoft.Network/virtualNetworks/subnets/join/action",
      "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action"
    ]
    not_actions = []
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/move/action",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action"
    ]
  }
}

#create artifact storage account and give the AIB identity access to it
resource "azurerm_storage_account" "aib_storage" {
  name                = var.aib_storage_account_name
  resource_group_name = var.rg_name

  location                          = var.rg_location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  public_network_access_enabled     = false
  infrastructure_encryption_enabled = true

  tags = var.tags
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

#configure the proxy subnet NSG to allow traffic
resource "azurerm_network_security_rule" "azure_image_builder" {
  name                        = "azure_image_builder_private_link_access"
  description                 = "Allow Image Builder Private Link Access to Proxy VM"
  priority                    = 1001
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "60000-60001"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = var.rg_name
  network_security_group_name = var.nsg_name
}