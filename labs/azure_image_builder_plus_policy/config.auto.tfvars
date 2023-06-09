prefix             = "aib"
region             = "westus3"
name_string_suffix = "a4"

hub_vnet_address_space = ["10.15.0.0/16"]
hub_subnets = [
  {
    name                                          = "AzureBastionSubnet",
    address_prefix                                = ["10.15.0.0/24"],
    private_endpoint_policies_enabled             = true,
    private_link_service_network_policies_enabled = true
  },
  {
    name                                          = "AzureFirewallSubnet"
    address_prefix                                = ["10.15.2.0/24"],
    private_endpoint_policies_enabled             = true,
    private_link_service_network_policies_enabled = true
  },
  {
    name                                          = "DCSubnet"
    address_prefix                                = ["10.15.3.0/24"],
    private_endpoint_policies_enabled             = true,
    private_link_service_network_policies_enabled = true
  }
]

spoke_vnet_address_space = ["10.30.0.0/16"]
spoke_subnets = [
  {
    name                                          = "VMSubnet",
    address_prefix                                = ["10.30.0.0/24"],
    private_endpoint_policies_enabled             = true,
    private_link_service_network_policies_enabled = true
  },
  {
    name                                          = "AIBSubnet",
    address_prefix                                = ["10.30.1.0/24"],
    private_endpoint_policies_enabled             = false,
    private_link_service_network_policies_enabled = false
  }
]
domain_fqdn = "azuretestzone.com"

tags = {
  environment = "AzAIBLab"
  CreatedBy   = "Terraform"
}

aib_role_scope = "/subscriptions/19fbc0d1-6eee-4268-a84a-3f06e7a69fca"
ext_role_scope = "/subscriptions/19fbc0d1-6eee-4268-a84a-3f06e7a69fca"


image_configurations = [
  {
    image_definition_name  = "linux_ubuntu_1804_hardened_test",
    template_file_name     = "linux_ubuntu_1804_hardened_base.json.tpl",
    os_type                = "Linux",
    hyper_v_generation     = "V1",
    image_publisher        = "customer_custom_images"
    image_offer            = "ubuntu-server"
    image_sku              = "18_04_lts_gen1_cis"
    run_output_name        = "linux_ubuntu_1804_run_output",
    replication_regions    = ["westus2", "westus3"],
    default_image_location = "westus3"
  }
]
