output "subnet_ids" {
  value = azurerm_subnet.subnets
}

output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  value = azurerm_virtual_network.vnet.name
}

output "vnet_cidr" {
  value = var.vnet_address_space[0]
}

output "vnet_nsgs" {
  value = azurerm_network_security_group.subnets
}