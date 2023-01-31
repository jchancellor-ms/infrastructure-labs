output "private_ip_address" {
  value = azurerm_network_interface.vm_nic.private_ip_address
}

output "mi_principal_id" {
  value = azurerm_linux_virtual_machine.this.identity[0].principal_id
}