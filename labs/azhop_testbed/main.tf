locals {
  name_string_suffix  = var.name_string_suffix
  resource_group_name = "${var.prefix}-rg-${var.region}-${local.name_string_suffix}"
  hub_vnet_name       = "${var.prefix}-vnet-hub-${var.region}-${local.name_string_suffix}"
  spoke_vnet_name     = "${var.prefix}-vnet-spoke-${var.region}-${local.name_string_suffix}"
  keyvault_name       = "${var.prefix}-kv-${var.region}-${local.name_string_suffix}"
  dc_vm_name          = "dc-${var.region}-${local.name_string_suffix}"
  bastion_name        = "${var.prefix}-bastion-${var.region}-${local.name_string_suffix}"

  config_values_dc = {
    active_directory_domain       = "azuretestzone.com"
    active_directory_netbios_name = "azuretestzone"
    vault_name                    = local.keyvault_name

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
  private_ip_address_1 = cidrhost(module.lab_hub_virtual_network.subnet_ids["DCSubnet"].address_prefixes[0], 100)
  availability_set_id  = azurerm_availability_set.domain_controllers.id
  config_values        = local.config_values_dc
  template_filename    = "dc_windows_dsc_azhop.ps1"

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]
}
