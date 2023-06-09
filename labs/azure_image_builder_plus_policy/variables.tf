variable "prefix" {}
variable "region" {}
variable "hub_vnet_address_space" {}
variable "hub_subnets" {}
variable "tags" {}
variable "domain_fqdn" {}
variable "name_string_suffix" {}
variable "spoke_vnet_address_space" {}
variable "spoke_subnets" {}
variable "aib_role_scope" {}
variable "ext_role_scope" {}
variable "image_configurations" {
    type = list(object({
    image_definition_name  = string
    template_file_name     = string
    os_type                = string
    hyper_v_generation     = string
    image_publisher        = string
    image_offer            = string
    image_sku              = string
    run_output_name        = string
    replication_regions    = list(string)
    default_image_location = string
  }))
}