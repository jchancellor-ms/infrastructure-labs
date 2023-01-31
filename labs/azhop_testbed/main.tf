locals {
  name_string_suffix  = var.name_string_suffix
  resource_group_name = "${var.prefix}-rg-${var.region}-${local.name_string_suffix}"
  hub_vnet_name       = "${var.prefix}-vnet-hub-${var.region}-${local.name_string_suffix}"
  spoke_vnet_name     = "${var.prefix}-vnet-spoke-${var.region}-${local.name_string_suffix}"
  keyvault_name       = "${var.prefix}-kv-${var.region}-${local.name_string_suffix}"
  dc_vm_name          = "dc-${var.region}-${local.name_string_suffix}"
  bastion_name        = "${var.prefix}-bastion-${var.region}-${local.name_string_suffix}"
  la_name             = "${var.prefix}-la-${var.region}-${local.name_string_suffix}"
  deployer_vm_name    = "dp-${var.region}-${local.name_string_suffix}"
  vm_vault_identity   = "vm-vault-identity-${local.name_string_suffix}"

  config_values_dc = {
    active_directory_domain       = "azuretestzone.com"
    active_directory_netbios_name = "azuretestzone"
    vault_name                    = local.keyvault_name

  }

  config_values_deployer = {
    file_content = base64encode(data.template_file.cloud_init_config.rendered)    
  }
}

###################################################################
# Create the core infrastructure
###################################################################
#deploy resource group
resource "azurerm_resource_group" "lab_rg" {
  name     = local.resource_group_name
  location = var.region
}

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

#deploy key vault with access policy and certificate issuer
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

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

module "lab_bastion" {
  source = "../../modules/lab_bastion_simple"

  bastion_name      = local.bastion_name
  rg_name           = azurerm_resource_group.lab_rg.name
  rg_location       = azurerm_resource_group.lab_rg.location
  bastion_subnet_id = module.lab_hub_virtual_network.subnet_ids["AzureBastionSubnet"].id
  tags              = var.tags
}

#deploy the DC first so that DNS is available for the k8s's servers to hit the internet
resource "azurerm_availability_set" "domain_controllers" {
  name                = "domain_controllers"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  tags                = var.tags
}

module "lab_dc" {
  source = "../../modules/lab_guest_server_2019_dc"

  rg_name              = azurerm_resource_group.lab_rg.name
  rg_location          = azurerm_resource_group.lab_rg.location
  vm_name_1            = local.dc_vm_name
  subnet_id            = module.lab_hub_virtual_network.subnet_ids["DCSubnet"].id
  vm_sku               = "Standard_D4as_v5"
  key_vault_id         = module.on_prem_keyvault_with_access_policy.keyvault_id
  keyvault_name        = local.keyvault_name
  private_ip_address_1 = cidrhost(module.lab_hub_virtual_network.subnet_ids["DCSubnet"].address_prefixes[0], 100)
  availability_set_id  = azurerm_availability_set.domain_controllers.id
  config_values        = local.config_values_dc
  template_filename    = "dc_windows_dsc_azhop.ps1"

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]
}

#create a log analytics workspace for any logs
module "log_analytics" {
  source = "../../modules/azure_log_analytics_simple"

  rg_name = azurerm_resource_group.lab_rg.name
  rg_location = azurerm_resource_group.lab_rg.location
  la_name = local.la_name
  tags = var.tags
}

resource "azurerm_user_assigned_identity" "vm_vault_identity" {
  location            = azurerm_resource_group.lab_rg.location
  name                = local.vm_vault_identity
  resource_group_name = azurerm_resource_group.lab_rg.name
}

#create a deployer machine for running the scripts
module "deployer_linux" {
  source = "../../modules/lab_guest_server_ubuntu"

  rg_name           = azurerm_resource_group.lab_rg.name
  rg_location       = azurerm_resource_group.lab_rg.location
  subnet_id         = module.lab_hub_virtual_network.subnet_ids["DCSubnet"].id
  vm_name           = local.deployer_vm_name
  vm_sku            = "Standard_D4as_v5"
  key_vault_id      = module.on_prem_keyvault_with_access_policy.keyvault_id
  #template_filename = "k8s_linux_node.yaml"
  template_filename = "azhop_cloudinit_config.yaml"
  config_values     = local.config_values_deployer
  vm_vault_identity = azurerm_user_assigned_identity.vm_vault_identity.id
}

data "azurerm_subscription" "primary" {
}

resource "azurerm_role_assignment" "sub_reader" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Reader"
  principal_id         = module.deployer_linux.mi_principal_id
}

resource "azurerm_role_assignment" "sub_uaa" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "User Access Administrator"
  principal_id         = module.deployer_linux.mi_principal_id
}

resource "azurerm_role_assignment" "rg_contributor" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Contributor"
  principal_id         = module.deployer_linux.mi_principal_id
}

data "template_file" "cloud_init_config" {
  template = file("${path.module}/../../templates/azhop_testconfig.yaml")
  vars     = {}  #add vars to file later to simplify redeployment
}

#give deployer VM rights secret read rights on the password keyvault
resource "azurerm_key_vault_access_policy" "deployment_user_access" {
  key_vault_id = module.on_prem_keyvault_with_access_policy.keyvault_id
  tenant_id    = data.azurerm_subscription.primary.tenant_id
  object_id    = module.deployer_linux.mi_principal_id

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Backup", "Recover", "Restore"
  ]

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]

}