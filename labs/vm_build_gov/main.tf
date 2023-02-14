locals {
  name_string_suffix       = var.name_string_suffix
  resource_group_name      = "${var.prefix}-rg-${var.region}-${local.name_string_suffix}"
  keyvault_name            = "${var.prefix}-kv-${var.region}-${local.name_string_suffix}"
  la_name                  = "${var.prefix}-la-${var.region}-${local.name_string_suffix}"
  aa_vault_identity        = "aa-vault-identity-${local.name_string_suffix}"
  aa_name                  = "${var.prefix}-aa-${var.region}-${local.name_string_suffix}"
  aa_diag_name             = "${var.prefix}-aa-diags-${var.region}-${local.name_string_suffix}"
  resource_group_name_test = "${var.prefix}-rg-test-${var.region}-${local.name_string_suffix}"
  hub_vnet_name            = "${var.prefix}-vnet-hub-${var.region}-${local.name_string_suffix}"
  spoke_vnet_name          = "${var.prefix}-vnet-spoke-${var.region}-${local.name_string_suffix}"
  dc_vm_name               = "dc-${var.region}-${local.name_string_suffix}"
  test_windows_vm_name     = "t1-${var.region}-${local.name_string_suffix}"
  config_values_windows    = {}


}

#create a resource group for the lab infra
resource "azurerm_resource_group" "lab_rg" {
  name     = local.resource_group_name
  location = var.region
}

#deploy key vault with access policy and certificate issuer
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

data "azurerm_subscription" "primary" {}

#create the keyvault to store the password secrets for newly created vms
module "on_prem_keyvault_with_access_policy" {
  source = "../../modules/avs_key_vault"

  #values to create the keyvault
  rg_name                   = azurerm_resource_group.lab_rg.name
  rg_location               = azurerm_resource_group.lab_rg.location
  keyvault_name             = local.keyvault_name
  azure_ad_tenant_id        = data.azurerm_client_config.current.tenant_id
  deployment_user_object_id = data.azuread_client_config.current.object_id
  tags                      = var.tags
}

#create a key for use for DSC encryption
resource "azurerm_key_vault_key" "dsc_key" {
  name         = "dsc-encryption-cert"
  key_vault_id = module.on_prem_keyvault_with_access_policy.keyvault_id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]
}

#user assigned managed identity for access to the dsc key
resource "azurerm_user_assigned_identity" "aa_vault_identity" {
  location            = azurerm_resource_group.lab_rg.location
  name                = local.aa_vault_identity
  resource_group_name = azurerm_resource_group.lab_rg.name
}

#give automation account vault identity key read rights on the keyvault
resource "azurerm_key_vault_access_policy" "deployment_user_access" {
  key_vault_id = module.on_prem_keyvault_with_access_policy.keyvault_id
  tenant_id    = azurerm_user_assigned_identity.aa_vault_identity.tenant_id
  object_id    = azurerm_user_assigned_identity.aa_vault_identity.principal_id

  key_permissions = [
    "Backup", "Create", "Decrypt", "Delete", "Encrypt", "Get", "Import", "List", "Purge", "Recover", "Restore", "Sign", "UnwrapKey", "Update", "Verify", "WrapKey", "Release", "Rotate", "GetRotationPolicy", "SetRotationPolicy"
  ]

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]

}

#create a log analytics workspace for containing the logs
module "log_analytics" {
  source = "../../modules/azure_log_analytics_simple"

  rg_name     = azurerm_resource_group.lab_rg.name
  rg_location = azurerm_resource_group.lab_rg.location
  la_name     = local.la_name
  tags        = var.tags
}

#Create an Automation account
resource "azurerm_automation_account" "lab_automation_account" {
  name                = local.aa_name
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  sku_name            = "Basic"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aa_vault_identity.id]
  }

  encryption {
    user_assigned_identity_id = azurerm_user_assigned_identity.aa_vault_identity.id
    key_source                = "Microsoft.Keyvault"
    key_vault_key_id          = azurerm_key_vault_key.dsc_key.id
  }

  tags = var.tags

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]
}

resource "azurerm_monitor_diagnostic_setting" "lab_aa_diag_setting" {
  name                       = local.aa_diag_name
  target_resource_id         = azurerm_automation_account.lab_automation_account.id
  log_analytics_workspace_id = module.log_analytics.log_analytics_id

  enabled_log {
    category_group = "AllLogs"

    retention_policy {
      enabled = false
    }
  }

  metric {
    category = "AllMetrics"

    retention_policy {
      enabled = false
    }
  }
}

#create a networking configuration
#Create a hub virtual network for the DC and the bastion for management
module "lab_hub_virtual_network" {
  source = "../../modules/lab_vnet_variable_subnets"

  rg_name            = azurerm_resource_group.lab_rg.name
  rg_location        = azurerm_resource_group.lab_rg.location
  vnet_name          = local.hub_vnet_name
  vnet_address_space = var.hub_vnet_address_space
  subnets            = var.hub_subnets
  tags               = var.tags
}

#create a spoke Vnet with custom DNS pointing to the DC
module "lab_spoke_virtual_network" {
  source = "../../modules/lab_vnet_variable_subnets"

  rg_name            = azurerm_resource_group.lab_rg.name
  rg_location        = azurerm_resource_group.lab_rg.location
  vnet_name          = local.spoke_vnet_name
  vnet_address_space = var.spoke_vnet_address_space
  subnets            = var.spoke_subnets
  tags               = var.tags
  is_spoke           = true
  dns_servers        = [cidrhost(module.lab_hub_virtual_network.subnet_ids["DCSubnet"].address_prefixes[0], 100), "168.63.129.16"]
}

#create peering to hub for spoke
module "azure_vnet_peering_hub_defaults" {
  source = "../../modules/lab_vnet_peering"

  spoke_vnet_name = local.spoke_vnet_name
  spoke_vnet_id   = module.lab_spoke_virtual_network.vnet_id
  hub_vnet_name   = local.hub_vnet_name
  hub_vnet_id     = module.lab_hub_virtual_network.vnet_id
  rg_name         = azurerm_resource_group.lab_rg.name

  depends_on = [
    module.lab_hub_virtual_network
  ]
}

#create a resource group for the test infra
resource "azurerm_resource_group" "test_rg" {
  name     = local.resource_group_name_test
  location = var.region
}

#deploy the test VM's (one linux one windows- no config)
### Deploy windows Node(s)
module "windows_node_servers" {
  source = "../../modules/lab_guest_server_windows_with_script"

  rg_name           = azurerm_resource_group.lab_rg.name
  rg_location       = azurerm_resource_group.lab_rg.location
  vm_name           = local.test_windows_vm_name
  subnet_id         = module.lab_spoke_virtual_network.subnet_ids["VMSubnet"].id
  vm_sku            = "Standard_D4as_v5"
  key_vault_id      = module.on_prem_keyvault_with_access_policy.keyvault_id
  os_sku            = "2022-Datacenter"
  template_filename = "empty.ps1"
  config_values     = local.config_values_windows
  keyvault_name     = local.keyvault_name

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]
}







