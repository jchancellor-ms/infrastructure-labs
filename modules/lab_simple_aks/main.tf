resource "azurerm_kubernetes_cluster" "simple" {
  name                = var.cluster_name
  location            = var.rg_location
  resource_group_name = var.rg_name
  dns_prefix          = var.dns_prefix
  automatic_channel_upgrade = stable
  oidc_issuer_enabled = true
  workload_identity_enabled = true


  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = var.vm_size
  }

  identity {
    type = "SystemAssigned"
  }



  tags = var.tags
}