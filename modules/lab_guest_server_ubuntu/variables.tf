variable "rg_name" {
  type        = string
  description = "Resource Group Name where the nva is deployed"
}

variable "rg_location" {
  type        = string
  description = "Resource Group location"
  default     = "westus2"
}

variable "subnet_id" {
  type        = string
  description = "subnet where the NVA will be deployed"
}

variable "vm_name" {
  type        = string
  description = "name for the linux vm"
}

variable "vm_sku" {
  type        = string
  description = "sku value for the vm deployment"
  default     = "Standard_B2ms"

}

variable "key_vault_id" {
  type        = string
  description = "the resource id for the keyvault where the password will be stored"
}

variable "has_config" {
  type        = string
  description = "the resource id for the keyvault where the password will be stored"
  default     = false
}

variable "config_values" {
  description = "map of variable values defined in the config template being deployed"
  default     = {}
}

variable "template_filename" {
  description = "filename of the cloud-init template to use. Leaving this unset will default to an empty template empty.yaml"
  type        = string
  default     = "empty.yaml"

}