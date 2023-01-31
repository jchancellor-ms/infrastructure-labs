variable "rg_name" {
  type        = string
  description = "Resource Group Name where log analytics workspace will be deployed"
}
variable "rg_location" {
  type        = string
  description = "Resource Group location"
  default     = "westus2"
}
variable "la_name" {
  type        = string
  description = "Azure Resource name for the log analytics workspace"
}
variable "tags" {
  type        = map(string)
  description = "List of the tags that will be assigned to each resource"
}





