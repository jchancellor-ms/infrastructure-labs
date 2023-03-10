variable "rg_name" {
  type        = string
  description = "The azure resource name for the resource group"
}

variable "rg_location" {
  type        = string
  description = "Resource Group region location"
  default     = "westus2"
}

variable "aib_identity_name" {
  type = string
}

variable "aib_role_name" {
  type = string
}

variable "aib_role_scope" {
  type = string
}

variable "image_gallery_name" {
  type = string
}

variable "tags" {
  type        = map(string)
  description = "List of the tags that will be assigned to each resource"
}

variable "nsg_name" {
  type        = string
  description = "NSG name for the nsg associated with the AIB subnet"
}

variable "aib_storage_account_name" {
  type        = string
  description = "Name to use for the AIB storage account used to store script artifacts"
}