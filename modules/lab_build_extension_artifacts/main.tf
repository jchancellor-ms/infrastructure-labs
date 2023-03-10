locals {
  ext_role_name    = "${var.prefix}-extension-add-custom-role-${random_string.namestring.result}"
  ext_sp_cert_name = "${var.prefix}-extension-add-service-principal-cert-${random_string.namestring.result}"
  ext_sp_app_name  = "${var.prefix}-sp-ext-add-${random_string.namestring.result}"
}

resource "random_string" "namestring" {
  length  = 4
  special = false
  upper   = false
  lower   = true
}

#create a custom role for the extension install service principal
#create custom role for AIB template and deployment script
resource "azurerm_role_definition" "ext_install_role" {
  name        = local.ext_role_name
  scope       = var.ext_role_scope
  description = "Used to allow newly built images to install build-related extensions"

  permissions {
    actions = [
      "Microsoft.Compute/locations/publishers/artifacttypes/types/read",
      "Microsoft.Compute/locations/publishers/artifacttypes/types/versions/read",
      "Microsoft.Compute/virtualMachineScaleSets/extensions/write",
      "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/extensions/read",
      "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/extensions/write",
      "Microsoft.Compute/virtualMachines/extensions/read",
      "Microsoft.Compute/virtualMachines/extensions/write"
    ]
    not_actions = []
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read"
    ]
  }
}
#create a private key pem certificate for use by the service principal
#and store key to the provisioning keyvault
resource "azurerm_key_vault_certificate" "ext_sp_cert" {
  name         = local.ext_sp_cert_name
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
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject            = "CN=${local.ext_sp_app_name}"
      validity_in_months = 12
    }
  }
}

data "azuread_client_config" "current" {}

#create the extension install application
resource "azuread_application" "ext_sp_app" {
  display_name = local.ext_sp_app_name
  owners       = [data.azuread_client_config.current.object_id]
}

#create the extension install service principal
resource "azuread_service_principal" "ext_sp" {
  application_id               = azuread_application.ext_sp_app.application_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

#associate the certificate with the service principal
resource "azuread_service_principal_certificate" "ext_sp_cert" {
  service_principal_id = azuread_service_principal.ext_sp.id
  type                 = "AsymmetricX509Cert"
  encoding             = "hex"
  value                = azurerm_key_vault_certificate.ext_sp_cert.certificate_data
  end_date             = azurerm_key_vault_certificate.ext_sp_cert.certificate_attribute[0].expires
}

#assign the role to the principal
resource "azurerm_role_assignment" "ext_sp_role_assignment" {
  scope              = var.ext_role_scope
  role_definition_id = azurerm_role_definition.ext_install_role.role_definition_resource_id
  principal_id       = azuread_service_principal.ext_sp.object_id
}

#create a keyvault access policy for the user managed identity used by Azure Image Builder so that it can read the certificate
resource "azurerm_key_vault_access_policy" "aib_user_identity_access" {
  key_vault_id = var.key_vault_id
  tenant_id    = data.azuread_client_config.current.tenant_id
  object_id    = var.aib_identity_object_id

  certificate_permissions = [
    "Get", "Create", "Delete", "DeleteIssuers", "GetIssuers", "Import", "List", "ListIssuers", "ManageContacts", "ManageIssuers", "Recover", "Restore", "SetIssuers", "Update"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Backup", "Recover", "Restore"
  ]

}