#create initial login password
resource "random_password" "userpass" {
  length           = 20
  special          = true
  override_special = "_-!."
  min_lower        = 2
  min_numeric      = 2
  min_upper        = 2
  min_special      = 2
}

#store the initial password in a key vault secret
resource "azurerm_key_vault_secret" "vmpassword" {
  name         = "${var.vm_name}-password"
  value        = random_password.userpass.result
  key_vault_id = var.key_vault_id
  depends_on   = [var.key_vault_id]
}

#create the nic
resource "azurerm_network_interface" "testnic" {
  name                = "${var.vm_name}-nic-1"
  location            = var.rg_location
  resource_group_name = var.rg_name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

#create the virtual machine
resource "azurerm_windows_virtual_machine" "this" {
  name                     = var.vm_name
  resource_group_name      = var.rg_name
  location                 = var.rg_location
  size                     = var.vm_sku
  admin_username           = "azureuser"
  admin_password           = random_password.userpass.result
  license_type             = "Windows_Server"
  enable_automatic_updates = true
  patch_mode               = "AutomaticByOS"

  network_interface_ids = [
    azurerm_network_interface.testnic.id,
  ]

  os_disk {
    name                 = "${var.vm_name}-OS"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = var.os_sku
    version   = "latest"
  }
}


data "template_file" "configure_node" {
  template = file("${path.module}/../../templates/${var.template_filename}")

  vars = var.config_values
}

#TODO: Consider moving all of this to DSC instead of powershell 
resource "azurerm_virtual_machine_extension" "configure_node" {
  name                 = "configure_node"
  virtual_machine_id   = azurerm_windows_virtual_machine.this.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.configure_node.rendered)}')) | Out-File -filepath configure_node.ps1\" && powershell -ExecutionPolicy Unrestricted -File configure_node.ps1"
    }
PROTECTED_SETTINGS

}

