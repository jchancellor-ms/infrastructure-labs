variable "image_definition_name" {
  type        = string
  description = "The name to use for the image definition being created."
}

variable "shared_gallery_name" {
  type        = string
  description = "the azure resource name for the image gallery"
}

variable "rg_name" {
  type        = string
  description = "The azure resource name for the resource group"
}

variable "rg_location" {
  type        = string
  description = "Resource Group region location"
  default     = "westus2"
}

variable "os_type" {
  type        = string
  description = "The OS type for the image being created. Either Windows or Linux"
}

variable "hyper_v_generation" {
  type        = string
  description = "the hyper-v generation value for the image. Either V1 or V2"
}

variable "image_publisher" {
  type        = string
  description = "The image publisher value for the target custom image."
}

variable "image_offer" {
  type        = string
  description = "The image offer value for the target custom image."
}

variable "image_sku" {
  type        = string
  description = "The image sku value for the target custom image."
}

variable "tags" {
  type        = map(string)
  description = "List of the tags that will be assigned to each resource"
}

variable "template_file_name" {
  type        = string
  description = "Name of the image build template file."
}

variable "run_output_name" {
  type        = string
  description = "Name of the custom image to create and distribute using Azure Image Builder."
}

variable "replication_regions" {
  type        = list(string)
  description = "List the regions in Azure where you would like to replicate the custom image after it is created."
  default     = ["westus3", "westus2"]
}

variable "default_image_location" {
  type        = string
  description = "The geo-location where the image template resource lives"
  default     = "westus3"
}

variable "aib_identity_id" {
  type        = string
  description = "Azure resource Id for the aib run managed identity"
}

variable "staging_resource_group_id" {
  type        = string
  description = "The resource group id for the staging resource group. Will be generated randomly if empty."
  default     = ""
}


variable "deploy_subnet_id" {
  type        = string
  description = "Subnet used for the proxy VM for AIB private link connection"
}

