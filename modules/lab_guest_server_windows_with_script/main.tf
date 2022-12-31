locals {
  config_values = merge(var.config_values, { admin_username = "azureuser", admin_password = random_password.userpass.result, dsc_cert_thumbprint = azurerm_key_vault_certificate.this.thumbprint, script_name = "${var.vm_name}-script" })
}

resource "random_string" "resources" {
  length  = 4
  special = false
  upper   = false
  lower   = true
}


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

  identity {
    type = "SystemAssigned"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = var.os_sku
    version   = "latest"
  }

  secret {
    certificate {
      store = "My"
      url   = azurerm_key_vault_certificate.this.secret_id
    }

    certificate {
      store = "Root"
      url   = azurerm_key_vault_certificate.this.secret_id
    }
    key_vault_id = var.key_vault_id
  }
}

#Add the virtual machine managed identity to the key vault access policy
#Come back and pare this down to secret and certificate permissions required to manage and rotate certs and secrets
resource "azurerm_key_vault_access_policy" "managed_identity_access" {
  key_vault_id = var.key_vault_id

  tenant_id = azurerm_windows_virtual_machine.this.identity[0].tenant_id
  object_id = azurerm_windows_virtual_machine.this.identity[0].principal_id

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
  name         = "dsc-cert-${random_string.resources.result}"
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
      extended_key_usage = ["1.3.6.1.5.5.7.3.1", "1.3.6.1.5.5.7.3.2", "2.5.29.37", "1.3.6.1.4.1.311.80.1"]

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

      subject            = "CN=${var.vm_name}"
      validity_in_months = 12
    }
  }
}

data "template_file" "configure_node" {
  template = file("${path.module}/../../templates/${var.template_filename}")
  vars     = local.config_values
}

data "template_file" "run_script" {
  template = file("${path.module}/../../templates/dsc_modules.ps1")
  vars     = local.config_values
}

#store the rendered script as a secret in the key vault
resource "azurerm_key_vault_secret" "vmscript" {
  name         = "${var.vm_name}-script"
  value        = base64encode(data.template_file.configure_node.rendered)
  key_vault_id = var.key_vault_id
  depends_on   = [var.key_vault_id]
}


#TODO: Consider moving all of this to DSC instead of powershell 
resource "azurerm_virtual_machine_extension" "run_script" {
  name                 = "${var.vm_name}-run-script"
  virtual_machine_id   = azurerm_windows_virtual_machine.this.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.run_script.rendered)}')) | Out-File -filepath run_script.ps1\" && powershell -ExecutionPolicy Unrestricted -File run_script.ps1"
    }
PROTECTED_SETTINGS

}

