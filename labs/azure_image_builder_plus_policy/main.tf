#create the image and publish to the gallery
locals {
  name_string_suffix  = var.name_string_suffix
  resource_group_name = "${var.prefix}-rg-${var.region}-${local.name_string_suffix}"
  keyvault_name       = "${var.prefix}-kv-${var.region}-${local.name_string_suffix}"
  aib_identity_name   = "aib-identity-${local.name_string_suffix}"
  aib_role_name       = "aib-role-${local.name_string_suffix}"
  image_gallery_name  = "aib-gallery-${local.name_string_suffix}"

}

#create a resource group for the lab infra
resource "azurerm_resource_group" "lab_rg" {
  name     = local.resource_group_name
  location = var.region
}


#create the image builder base module
module "image_builder_base" {
  source = "../../modules/lab_image_builder_base"

  rg_name            = azurerm_resource_group.lab_rg.name
  rg_location        = azurerm_resource_group.lab_rg.location
  aib_identity_name  = local.aib_identity_name
  aib_role_name      = local.aib_role_name
  aib_role_scope     = var.aib_role_scope
  image_gallery_name = local.image_gallery_name
  tags               = var.tags
}

#create the image template resource
module "template_windows_2019_hardened_w_extensions" {
  source = "../../templates/image_templates/lab_image_builder_base"

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
}