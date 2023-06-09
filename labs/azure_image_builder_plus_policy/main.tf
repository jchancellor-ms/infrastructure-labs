#create the image and publish to the gallery
locals {
  name_string_suffix       = var.name_string_suffix
  resource_group_name      = "${var.prefix}-rg-${var.region}-${local.name_string_suffix}"
  keyvault_name            = "${var.prefix}-kv-${var.region}-${local.name_string_suffix}"
  aib_identity_name        = "aib-identity-${local.name_string_suffix}"
  aib_role_name            = "aib-role-${local.name_string_suffix}"
  image_gallery_name       = "aib_gallery_${local.name_string_suffix}"
  aib_storage_account_name = "aibstg${local.name_string_suffix}${random_string.namestring.result}"
  spoke_vnet_name          = "${var.prefix}-vnet-spoke-${var.region}-${local.name_string_suffix}"
}

resource "random_string" "namestring" {
  length  = 4
  special = false
  upper   = false
  lower   = true
}


#create a resource group for the lab infra
resource "azurerm_resource_group" "lab_rg" {
  name     = local.resource_group_name
  location = var.region
}

#create a vnet for use by image builder for private access 
module "lab_spoke_virtual_network" {
  source = "../../modules/lab_vnet_variable_subnets"

  rg_name            = azurerm_resource_group.lab_rg.name
  rg_location        = azurerm_resource_group.lab_rg.location
  vnet_name          = local.spoke_vnet_name
  vnet_address_space = var.spoke_vnet_address_space
  subnets            = var.spoke_subnets
  tags               = var.tags
  is_spoke           = true
  #dns_servers        = [cidrhost(module.lab_hub_virtual_network.subnet_ids["DCSubnet"].address_prefixes[0], 100), "168.63.129.16"]
}

#create a keyvault to store any build related secrets for keys
#deploy key vault with access policy 
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



#create the image builder base module to create the image builder supporting resources
module "image_builder_base" {
  source = "../../modules/lab_image_builder_base"

  rg_name                  = azurerm_resource_group.lab_rg.name
  rg_location              = azurerm_resource_group.lab_rg.location
  aib_identity_name        = local.aib_identity_name
  aib_role_name            = local.aib_role_name
  aib_role_scope           = var.aib_role_scope
  image_gallery_name       = local.image_gallery_name
  tags                     = var.tags
  nsg_name                 = module.lab_spoke_virtual_network.vnet_nsgs["AIBSubnet"].name
  aib_storage_account_name = local.aib_storage_account_name
}

#create the service principal artifacts necessary to run cli commands on images
module "lab_build_extension_artifacts" {
  source = "../../modules/lab_build_extension_artifacts"

  key_vault_id           = module.on_prem_keyvault_with_access_policy.keyvault_id
  prefix                 = "aibtest"
  ext_role_scope         = var.ext_role_scope
  aib_identity_object_id = module.image_builder_base.aib_user_managed_identity_object_id
  depends_on = [
    module.on_prem_keyvault_with_access_policy,
    module.image_builder_base
  ]
}

#create all of the defined templates in the config file
module "create_image_builder_templates" {
  source   = "../../modules/lab_build_image_template_private_network"
  for_each = { for image in var.image_configurations : image.image_definition_name => image }

  image_definition_name     = each.value.image_definition_name
  shared_gallery_name       = module.image_builder_base.aib_shared_gallery_name
  rg_name                   = azurerm_resource_group.lab_rg.name
  rg_location               = azurerm_resource_group.lab_rg.location
  os_type                   = each.value.os_type
  hyper_v_generation        = each.value.hyper_v_generation
  image_publisher           = each.value.image_publisher
  image_offer               = each.value.image_offer
  image_sku                 = each.value.image_sku
  tags                      = var.tags
  template_file_name        = each.value.template_file_name
  run_output_name           = each.value.run_output_name
  replication_regions       = each.value.replication_regions
  default_image_location    = each.value.default_image_location
  aib_identity_id           = module.image_builder_base.aib_user_managed_identity_id
  staging_resource_group_id = ""
  deploy_subnet_id          = module.lab_spoke_virtual_network.subnet_ids["AIBSubnet"].id
}

/*
#create the image template resource
module "template_windows_2019_hardened_w_extensions" {
  source = "../../templates/image_templates/windows_2019_hardened_w_extensions"

  default_image_location    = "westus3"
  resource_group_id         = azurerm_resource_group.lab_rg.id
  tags                      = var.tags
  run_output_name           = "Win2019_AzureWindowsBaseline_CustomImage"
  aib_identity_id           = module.image_builder_base.aib_user_managed_identity_id
  replication_regions       = ["westus3", "westus2"]
  staging_resource_group_id = null
  rg_name                   = azurerm_resource_group.lab_rg.name
  rg_location               = azurerm_resource_group.lab_rg.location
  shared_gallery_name       = module.image_builder_base.aib_shared_gallery_name
  deploy_subnet_id          = module.lab_spoke_virtual_network.subnet_ids["AIBSubnet"].id
  customizer_script_uri     = "https://raw.githubusercontent.com/jchancellor-ms/infrastructure-labs/main/templates/image_scripts/windowsCustomization.ps1"

  depends_on = [
    module.image_builder_base,
    module.lab_spoke_virtual_network
  ]
}
*/
