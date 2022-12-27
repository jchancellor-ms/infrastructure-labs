locals {
  name_string_suffix  = var.name_string_suffix
  resource_group_name = "${var.prefix}-rg-${var.region}-${local.name_string_suffix}"
  hub_vnet_name       = "${var.prefix}-vnet-hub-${var.region}-${local.name_string_suffix}"
  spoke_vnet_name     = "${var.prefix}-vnet-spoke-${var.region}-${local.name_string_suffix}"
  keyvault_name       = "${var.prefix}-kv-${var.region}-${local.name_string_suffix}"
  dc_vm_name          = "dc-${var.region}-${local.name_string_suffix}"
  k8s_vm_name         = "k8-${var.region}-${local.name_string_suffix}"
  k8s_linux_vm_name   = "kl-${var.region}-${local.name_string_suffix}"
  k8s_windows_vm_name = "kw-${var.region}-${local.name_string_suffix}"
  bastion_name        = "${var.prefix}-bastion-${var.region}-${local.name_string_suffix}"
  ou_name             = "k8s"
  ou                  = "OU=${local.ou_name},${join(",", [for name in split(".", var.domain_fqdn) : "DC=${name}"])}"

  config_values = {
    node_token_value = "${random_string.node_part1.result}.${random_string.node_part2.result}"
    node_token_hash  = sha256("${random_string.node_part1.result}.${random_string.node_part2.result}")
    control_node_ip  = module.k8s_server.private_ip_address
  }

  config_values_windows = {
    dsc_uri     = "https://raw.githubusercontent.com/jchancellor-ms/infrastructure-labs/main/templates/k8s_windows_dsc.ps1"
    dsc_outfile = "k8s_windows_dsc.ps1"
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
  dns_servers        = [cidrhost(module.lab_hub_virtual_network.subnet_ids["DCSubnet"].address_prefixes[0], 100)]
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

  rg_name                       = azurerm_resource_group.lab_rg.name
  rg_location                   = azurerm_resource_group.lab_rg.location
  vm_name_1                     = local.dc_vm_name
  subnet_id                     = module.lab_hub_virtual_network.subnet_ids["DCSubnet"].id
  vm_sku                        = "Standard_D4as_v5"
  key_vault_id                  = module.on_prem_keyvault_with_access_policy.keyvault_id
  active_directory_domain       = var.domain_fqdn
  active_directory_netbios_name = split(".", var.domain_fqdn)[0]
  private_ip_address_1          = cidrhost(module.lab_hub_virtual_network.subnet_ids["DCSubnet"].address_prefixes[0], 100)
  ou_name                       = local.ou_name
  availability_set_id           = azurerm_availability_set.domain_controllers.id

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]
}

###
module "k8s_server" {
  source = "../../modules/lab_guest_server_ubuntu"

  rg_name           = azurerm_resource_group.lab_rg.name
  rg_location       = azurerm_resource_group.lab_rg.location
  subnet_id         = module.lab_spoke_virtual_network.subnet_ids["K8sSubnet"].id
  vm_name           = local.k8s_vm_name
  vm_sku            = "Standard_D4as_v5"
  key_vault_id      = module.on_prem_keyvault_with_access_policy.keyvault_id
  template_filename = "k8s.yaml"
  #template_filename         = "empty.yaml"
  config_values = local.config_values

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]
}



##### generate the kubernetes node join config
resource "random_string" "node_part1" {
  length  = 6
  special = false
  upper   = false
  lower   = true
}

resource "random_string" "node_part2" {
  length  = 16
  special = false
  upper   = false
  lower   = true
}


output "node_hash" {
  value = local.config_values.node_token_hash
  #sensitive = true
}

#create a second linux node and join it to the node pool.  (allows calico to run pods on a non control plane node?)
module "k8s_server_linux" {
  source = "../../modules/lab_guest_server_ubuntu"

  rg_name           = azurerm_resource_group.lab_rg.name
  rg_location       = azurerm_resource_group.lab_rg.location
  subnet_id         = module.lab_spoke_virtual_network.subnet_ids["K8sSubnet"].id
  vm_name           = local.k8s_linux_vm_name
  vm_sku            = "Standard_D4as_v5"
  key_vault_id      = module.on_prem_keyvault_with_access_policy.keyvault_id
  template_filename = "k8s_linux_node.yaml"
  #template_filename         = "empty.yaml"
  config_values = local.config_values

  depends_on = [
    module.k8s_server
  ]
}

resource "azurerm_availability_set" "windows_nodes" {
  name                = "windows_nodes"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  tags                = var.tags
}

### Deploy windows Node(s)
module "windows_node_servers" {
  source = "../../modules/lab_guest_server_windows_with_script"

  rg_name           = azurerm_resource_group.lab_rg.name
  rg_location       = azurerm_resource_group.lab_rg.location
  vm_name           = local.k8s_windows_vm_name
  subnet_id         = module.lab_spoke_virtual_network.subnet_ids["K8sSubnet"].id
  vm_sku            = "Standard_D4as_v5"
  key_vault_id      = module.on_prem_keyvault_with_access_policy.keyvault_id
  os_sku            = "2022-Datacenter"
  template_filename = "k8s_windows_ps.ps1"
  config_values     = local.config_values_windows
  #availability_set_id       = azurerm_availability_set.windows_nodes.id

  depends_on = [
    module.lab_dc,
    module.on_prem_keyvault_with_access_policy,
  ]
}

