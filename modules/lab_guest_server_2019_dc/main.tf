locals {
  dc_config_values = merge(var.config_values, { admin_username = "azureuser", admin_password = random_password.userpass.result, dsc_cert_thumbprint = azurerm_key_vault_certificate.this.thumbprint })
}

resource "random_password" "userpass" {
  length           = 20
  special          = true
  override_special = "_-!."
  min_lower        = 2
  min_numeric      = 2
  min_upper        = 2
  min_special      = 2
}

resource "azurerm_key_vault_secret" "vmpassword" {
  name         = "${var.vm_name_1}-password"
  value        = random_password.userpass.result
  key_vault_id = var.key_vault_id
  depends_on   = [var.key_vault_id]
}

##################################################################################
# Configure the first DC
##################################################################################
resource "azurerm_network_interface" "testnic" {
  name                = "${var.vm_name_1}-nic-1"
  location            = var.rg_location
  resource_group_name = var.rg_name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ip_address_1
  }
}

resource "azurerm_windows_virtual_machine" "primary" {
  name                     = var.vm_name_1
  resource_group_name      = var.rg_name
  location                 = var.rg_location
  size                     = var.vm_sku
  admin_username           = "azureuser"
  admin_password           = random_password.userpass.result
  license_type             = "Windows_Server"
  enable_automatic_updates = true
  patch_mode               = "AutomaticByOS"
  availability_set_id      = var.availability_set_id

  network_interface_ids = [
    azurerm_network_interface.testnic.id,
  ]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

 secret {
  certificate {
      store = "My"
      url = azurerm_key_vault_certificate.this.secret_id
    }
  certificate {
      store = "Root"
      url = azurerm_key_vault_certificate.this.secret_id
    }
  key_vault_id = var.key_vault_id
 }

  identity {
    type = "SystemAssigned"
  }
}


#Add the virtual machine managed identity to the key vault access policy
resource "azurerm_key_vault_access_policy" "managed_identity_access" {
  key_vault_id = var.key_vault_id

  tenant_id    = azurerm_windows_virtual_machine.primary.identity[0].tenant_id
  object_id    = azurerm_windows_virtual_machine.primary.identity[0].principal_id

  certificate_permissions = [
    "Get", "Create", "Delete", "DeleteIssuers", "GetIssuers", "Import", "List", "ListIssuers", "ManageContacts", "ManageIssuers", "Recover", "Restore", "SetIssuers", "Update"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Backup", "Recover", "Restore"
  ]

  storage_permissions = [
    "Backup", "Delete", "DeleteSAS", "Get", "GetSAS", "List", "ListSAS", "Recover", "RegenerateKey", "Restore", "Set", "SetSAS", "Update"
  ]

  key_permissions = [
    "Backup", "Create", "Decrypt", "Delete", "Encrypt", "Get", "Import", "List", "Purge", "Recover", "Restore", "Sign", "UnwrapKey", "Update", "Verify", "WrapKey", "Release", "Rotate", "GetRotationPolicy", "SetRotationPolicy"
  ]
}

#Create a certificate for DSC to use
resource "azurerm_key_vault_certificate" "this" {
  name         = "dsc-cert"
  key_vault_id = var.key_vault_id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      # Server Authentication = 1.3.6.1.5.5.7.3.1
      # Client Authentication = 1.3.6.1.5.5.7.3.2
      extended_key_usage = ["1.3.6.1.5.5.7.3.1", "1.3.6.1.5.5.7.3.2", "2.5.29.37", "1.3.6.1.4.1.311.80.1" ]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject_alternative_names {
        dns_names = var.cert_san_names
      }

      subject            = "CN=${var.vm_name_1}"
      validity_in_months = 12
    }
  }
}


#generate the powershell and dsc template file for execution by the vm
data "template_file" "configure_primary_dc" {
  template = file("${path.module}/../../templates/${var.template_filename}")

  vars = local.dc_config_values
}

data "template_file" "install_modules" {
  template = file("${path.module}/../../templates/dsc_modules.ps1")
}

#TODO: Consider moving all of this to DSC instead of powershell 
resource "azurerm_virtual_machine_extension" "configure_primary_dc" {
  name                 = "configure_primary_dc"
  virtual_machine_id   = azurerm_windows_virtual_machine.primary.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.configure_primary_dc.rendered)}')) | Out-File -filepath configure_primary_dc.ps1\" && powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.install_modules.rendered)}')) | Out-File -filepath install_modules.ps1\" && powershell -ExecutionPolicy Unrestricted -File install_modules.ps1 && powershell -ExecutionPolicy Unrestricted -File configure_primary_dc.ps1"
    }
PROTECTED_SETTINGS

}

##################################################################################
# Configure the second DC
##################################################################################
# TODO: Update this to add a second DC 