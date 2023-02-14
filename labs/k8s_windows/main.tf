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
  vm_vault_identity   = "vm-vault-identity-${local.name_string_suffix}"

  config_values = {
    node_token_value = "${random_string.node_part1.result}.${random_string.node_part2.result}"
    vault_name       = local.keyvault_name
    hash_name        = "${var.prefix}-ca-hash-${local.name_string_suffix}"
    version_name     = "${var.prefix}-k8s-version-${local.name_string_suffix}"
    conf_secret_name = "${var.prefix}-k8s-conf-${local.name_string_suffix}"
    control_node_ip  = module.k8s_server.private_ip_address
  }

  config_values_windows = {
    k8s_version      = data.azurerm_key_vault_secret.k8s_version.value
    node_token_value = "${random_string.node_part1.result}.${random_string.node_part2.result}"
    hash_name        = "${var.prefix}-ca-hash-${local.name_string_suffix}"
    version_name     = "${var.prefix}-k8s-version-${local.name_string_suffix}"
    conf_secret_name = "${var.prefix}-k8s-conf-${local.name_string_suffix}"
    control_node_ip  = module.k8s_server.private_ip_address
  }

  config_values_dc = {
    active_directory_domain       = "azuretestzone.com"
    active_directory_netbios_name = "azuretestzone"
    app_ad_user                   = "testgmsaapp"
    app_ad_user_pass              = random_password.userpass.result
    gmsa_group_name               = "testgmsagroup"
    gmsa_account_name             = "testgmsaaccount"

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
  template_filename    = "dc_windows_dsc.ps1"

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]
}
##create a user-assigned managed identity and provision it with secrets get and create writes on the keyvault
resource "azurerm_user_assigned_identity" "vm_vault_identity" {
  location            = azurerm_resource_group.lab_rg.location
  name                = local.vm_vault_identity
  resource_group_name = azurerm_resource_group.lab_rg.name
}

resource "azurerm_key_vault_access_policy" "user_managed_identity_access" {
  key_vault_id = module.on_prem_keyvault_with_access_policy.keyvault_id

  tenant_id = azurerm_user_assigned_identity.vm_vault_identity.tenant_id
  object_id = azurerm_user_assigned_identity.vm_vault_identity.principal_id

  certificate_permissions = [
    "Get", "Create", "Import", "List", "ListIssuers", "ManageContacts", "ManageIssuers", "Recover", "Restore", "SetIssuers", "Update"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Backup", "Recover", "Restore"
  ]
}


#Build the credentialSpec template and upload it to the key vault
#add the general user credential to the vault for use in the template
resource "azurerm_key_vault_secret" "gmsa_user_cred" {
  name         = "gmsa-user"
  value        = "${local.config_values_dc.active_directory_domain}\\${local.config_values_dc.app_ad_user}:${random_password.userpass.result}"
  key_vault_id = module.on_prem_keyvault_with_access_policy.keyvault_id
  depends_on   = [module.on_prem_keyvault_with_access_policy]
}

#get the SID and GUID values and merge with the existing local values
data "azurerm_key_vault_secret" "domain_sid" {
  name         = "domain-sid"
  key_vault_id = module.on_prem_keyvault_with_access_policy.keyvault_id
  depends_on = [
    module.lab_dc,
    time_sleep.wait_600_seconds,
    module.on_prem_keyvault_with_access_policy
  ]
}

data "azurerm_key_vault_secret" "domain_guid" {
  name         = "domain-guid"
  key_vault_id = module.on_prem_keyvault_with_access_policy.keyvault_id
  depends_on = [
    module.lab_dc,
    time_sleep.wait_600_seconds,
    module.on_prem_keyvault_with_access_policy
  ]
}

data "template_file" "credential_spec" {
  template = file("${path.module}/../../templates/credentialSpec.yaml")
  vars = merge(local.config_values_dc, {
    domain_sid       = data.azurerm_key_vault_secret.domain_sid.value,
    domain_guid      = data.azurerm_key_vault_secret.domain_guid.value,
    user_assigned_mi = azurerm_user_assigned_identity.vm_vault_identity.principal_id,
  secret_url = azurerm_key_vault_secret.gmsa_user_cred.versionless_id })
}

#store the rendered script as a secret in the key vault
resource "azurerm_key_vault_secret" "credential_spec" {
  name         = "credential-spec"
  value        = base64encode(data.template_file.credential_spec.rendered)
  key_vault_id = module.on_prem_keyvault_with_access_policy.keyvault_id
}


#wait for the dc to build and reboot
resource "time_sleep" "wait_600_seconds" {
  depends_on = [module.lab_dc]

  create_duration = "900s"
}

### Create the kubernetes control node
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
  config_values     = local.config_values
  vm_vault_identity = azurerm_user_assigned_identity.vm_vault_identity.id

  depends_on = [
    module.lab_dc,
    time_sleep.wait_600_seconds,
    module.on_prem_keyvault_with_access_policy,
    azurerm_key_vault_secret.credential_spec
  ]
}

#allow time for the control pods to come up cleanly
resource "time_sleep" "wait_300_seconds" {
  depends_on = [module.k8s_server]

  create_duration = "300s"
}

#get the kubernetes version installed on the control node
data "azurerm_key_vault_secret" "k8s_version" {
  name         = local.config_values.version_name
  key_vault_id = module.on_prem_keyvault_with_access_policy.keyvault_id
  depends_on = [
    time_sleep.wait_300_seconds
  ]
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
  config_values     = local.config_values
  vm_vault_identity = azurerm_user_assigned_identity.vm_vault_identity.id

  depends_on = [
    module.lab_dc,
    time_sleep.wait_600_seconds,
    module.k8s_server,
    time_sleep.wait_300_seconds
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
  template_filename = "k8s_windows_dsc.ps1"
  #template_filename = "empty.ps1"
  config_values = local.config_values_windows
  #availability_set_id       = azurerm_availability_set.windows_nodes.id
  keyvault_name = local.keyvault_name

  depends_on = [
    module.lab_dc,
    module.on_prem_keyvault_with_access_policy,
    time_sleep.wait_600_seconds,
    module.k8s_server,
    time_sleep.wait_300_seconds
  ]
}

#create a gmsa user password
resource "random_password" "userpass" {
  length           = 20
  special          = true
  override_special = "_-!."
  min_lower        = 2
  min_numeric      = 2
  min_upper        = 2
  min_special      = 2
}

resource "azurerm_key_vault_secret" "gmsapassword" {
  name         = "testgmsaapp-password"
  value        = random_password.userpass.result
  key_vault_id = module.on_prem_keyvault_with_access_policy.keyvault_id
  depends_on   = [module.on_prem_keyvault_with_access_policy]
}


