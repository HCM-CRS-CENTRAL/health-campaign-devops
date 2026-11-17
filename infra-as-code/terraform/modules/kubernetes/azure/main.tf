resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.name}"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group}"
  dns_prefix          = "${var.name}"

  
  default_node_pool {
    name       = "nodepool1"
    temporary_name_for_rotation = "temprotate"
    node_count = "${var.node_count}"
    max_pods   = "100"
    vm_size    = "${var.vm_size}"
    vnet_subnet_id = "${var.vnet_subnet_id}"
    node_public_ip_enabled = false
    os_disk_size_gb = var.os_disk_size_gb
    auto_scaling_enabled = var.enable_auto_scaling
    min_count = var.enable_auto_scaling ? var.min_node_count : null
    max_count = var.enable_auto_scaling ? var.max_node_count : null
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  # Cluster identity: a system-assigned managed identity by default, or -- when
  # service_principal_client_id is set -- run as that service principal (as Togo does).
  # A managed identity only gets rights in the MC_ node resource group, so with a subnet
  # in our own VNet it additionally needs "Network Contributor" on that subnet (which
  # requires roleAssignments/write). A service principal that already has Contributor /
  # Network Contributor on the subscription needs no extra role assignment.
  # NOTE: switching between the two forces the cluster to be recreated.
  dynamic "identity" {
    for_each = var.service_principal_client_id == null ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  dynamic "service_principal" {
    for_each = var.service_principal_client_id == null ? [] : [1]
    content {
      client_id     = var.service_principal_client_id
      client_secret = var.service_principal_client_secret
    }
  }

  oidc_issuer_enabled       = var.oidc_issuer_enabled
  workload_identity_enabled = var.workload_identity_enabled

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"  # Enable CNI Overlay mode
    outbound_type       = "userAssignedNATGateway" # Use NAT Gateway
    dns_service_ip      = "172.17.0.10"  # Changed to avoid conflicts
    service_cidr        = "172.17.0.0/16" # Changed from 10.2.0.0/16
    pod_cidr            = "192.168.0.0/16" # Pod CIDR for overlay mode
  }

  # oms_agent {
  #   log_analytics_workspace_id      = azurerm_log_analytics_workspace.logs_workspace.id
  # }

  tags = {
    Environment = "${var.environment}"
    ManagedBy = "Terraform"
    Project = "crs-central-instance"
    "appcode"     = "crs-central-instance"
  }

  lifecycle {
    # Microsoft Defender for Containers is enabled at subscription level (Defender for
    # Cloud / Azure Policy), which attaches a microsoft_defender block outside Terraform.
    # Without this, every plan tries to remove it.
    ignore_changes = [microsoft_defender]
  }
}

# resource "azurerm_log_analytics_workspace" "logs_workspace" {
#   name                = "${var.name}-logs-workspace"
#   location            = "${var.location}"
#   resource_group_name = "${var.resource_group}"

#   sku                 = "PerGB2018"
#   retention_in_days   = 30

# }
