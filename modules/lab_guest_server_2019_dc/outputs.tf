output "dc_join_password" {
  value     = random_password.userpass.result
  sensitive = true
}

output "dsc_cert_thumbprint" {
  value = azurerm_key_vault_certificate.this.thumbprint
}
