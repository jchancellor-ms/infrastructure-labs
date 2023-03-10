output "aib_user_managed_identity_id" {
  value = azurerm_user_assigned_identity.AIB_Identity.id
}

output "aib_shared_gallery_name" {
  value = azurerm_shared_image_gallery.AIB_image_gallery.name
}

output "aib_user_managed_identity_object_id" {
  value = azurerm_user_assigned_identity.AIB_Identity.principal_id
}