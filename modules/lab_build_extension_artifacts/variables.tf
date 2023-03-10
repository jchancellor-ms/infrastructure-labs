variable "prefix" {
  type = string
}

variable "ext_role_scope" {
  type        = string
  description = "Scope ID where the extension deployment service principal and role will be applied"
}

variable "key_vault_id" {
  type        = string
  description = "The resource id of the keyvault used to hold the service principal certificate"
}

variable "aib_identity_object_id" {
  type = string
}