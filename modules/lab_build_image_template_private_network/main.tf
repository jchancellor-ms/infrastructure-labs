#create the image resource
resource "azurerm_shared_image" "this_image" {
  name                = var.image_definition_name
  gallery_name        = var.shared_gallery_name
  resource_group_name = var.rg_name
  location            = var.rg_location
  os_type             = var.os_type
  hyper_v_generation  = var.hyper_v_generation

  identifier {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
  }
}

data "template_file" "image_template" {
  template = file("${path.module}/templates/${var.template_file_name}")

  vars = {
    gallery_image_id          = azurerm_shared_image.this_image.id
    run_output_name           = var.run_output_name
    aib_identity_id           = var.aib_identity_id
    deploy_subnet_id          = var.deploy_subnet_id
    staging_resource_group_id = var.staging_resource_group_id
    replication_regions       = jsonencode(var.replication_regions)

  }
}

data "azurerm_resource_group" "template_rg" {
  name = var.rg_name
}


resource "azapi_resource" "image_template_ws2019_hardened_w_extensions" {
  type      = "Microsoft.VirtualMachineImages/imageTemplates@2022-02-14"
  name      = "test_image_template_name" #var.image_template_name
  location  = var.default_image_location
  parent_id = data.azurerm_resource_group.template_rg.id
  tags      = var.tags
  identity {
    type         = "UserAssigned"
    identity_ids = [var.aib_identity_id]
  }
  body = data.template_file.image_template.rendered
}
