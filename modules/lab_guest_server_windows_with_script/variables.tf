variable "rg_name" {
  type        = string
  description = "The azure resource name for the resource group"
}
variable "rg_location" {
  type        = string
  description = "Resource Group region location"
  default     = "westus2"
}
variable "vm_name" {
  type        = string
  description = "The azure resource name for the virtual machine"
}

variable "subnet_id" {
  type        = string
  description = "The resource ID for the subnet where the virtual machine will be deployed"
}
variable "vm_sku" {
  type        = string
  description = "The sku value for the virtual machine being deployed"
}
variable "key_vault_id" {
  type        = string
  description = "The resource ID for the key vault where the virtual machine secrets will be deployed"
}

variable "os_sku" {
  type        = string
  description = "The OS sku value for the windows server"
}

variable "template_filename" {
  description = "filename of the powershell script template to use in the custom script extension. Leaving this unset will default to an empty template empty.ps1"
  type        = string
  default     = "empty.ps1"
}

variable "config_values" {
  description = "map of variable values defined in the config template being deployed"
  default     = {}
}