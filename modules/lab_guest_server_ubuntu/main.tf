

#generate the cloud init config file
data "template_file" "cloud_init_config" {
  template = file("${path.module}/../../templates/${var.template_filename}")
  vars     = var.config_values
}

data "template_cloudinit_config" "config" {
  gzip          = false
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content      = data.template_file.cloud_init_config.rendered
  }
}


resource "random_password" "admin_password" {
  length           = 20
  special          = true
  override_special = "_-!."
  min_lower        = 2
  min_numeric      = 2
  min_upper        = 2
  min_special      = 2
}

resource "azurerm_network_interface" "vm_nic" {
  name                 = "${var.vm_name}-nic-1"
  location             = var.rg_location
  resource_group_name  = var.rg_name
  enable_ip_forwarding = true

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                            = var.vm_name
  resource_group_name             = var.rg_name
  location                        = var.rg_location
  size                            = var.vm_sku
  admin_username                  = "azureuser"
  admin_password                  = random_password.admin_password.result
  disable_password_authentication = false
  custom_data                     = data.template_cloudinit_config.config.rendered

  network_interface_ids = [
    azurerm_network_interface.vm_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.vm_vault_identity]
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}


#write secret to keyvault
resource "azurerm_key_vault_secret" "admin_password" {
  name         = "${var.vm_name}-azureuser-password"
  value        = random_password.admin_password.result
  key_vault_id = var.key_vault_id
}

resource "azurerm_managed_disk" "this" {
  name                 = "${azurerm_linux_virtual_machine.this.name}-disk1"
  location             = var.rg_location
  resource_group_name  = var.rg_name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
}

resource "azurerm_virtual_machine_data_disk_attachment" "this" {
  managed_disk_id    = azurerm_managed_disk.this.id
  virtual_machine_id = azurerm_linux_virtual_machine.this.id
  lun                = "10"
  caching            = "ReadWrite"
}