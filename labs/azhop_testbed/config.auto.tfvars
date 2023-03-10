prefix             = "azhoplab"
region             = "westus3"
name_string_suffix = "a1"

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
  }
]
domain_fqdn = "azuretestzone.com"

tags = {
  environment = "AzHopLab"
  CreatedBy   = "Terraform"
}
