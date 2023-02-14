prefix             = "aib"
region             = "westus3"
name_string_suffix = "a1"

hub_vnet_address_space = ["10.15.0.0/16"]
hub_subnets = [
  {
    name           = "AzureBastionSubnet",
    address_prefix = ["10.15.0.0/24"]
  },
  {
    name           = "AzureFirewallSubnet"
    address_prefix = ["10.15.2.0/24"]
  },
  {
    name           = "DCSubnet"
    address_prefix = ["10.15.3.0/24"]
  }
]

spoke_vnet_address_space = ["10.30.0.0/16"]
spoke_subnets = [
  {
    name           = "VMSubnet",
    address_prefix = ["10.30.0.0/24"]
  }
]
domain_fqdn = "azuretestzone.com"

tags = {
  environment = "AzAIBLab"
  CreatedBy   = "Terraform"
}

aib_role_scope = "/subscriptions/19fbc0d1-6eee-4268-a84a-3f06e7a69fca"
