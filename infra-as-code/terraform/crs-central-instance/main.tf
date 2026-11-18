provider "azurerm" {
  features {}
  subscription_id = "f07cf9be-deef-46d7-b025-fd11d032da4f"
  resource_provider_registrations = "none"

  # Service Principal authentication (uses environment variables if not specified)
  # ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
}

terraform {
  backend "azurerm" {
    resource_group_name  = "crs-central-instance-rg"
    storage_account_name = "tfstatezxqg9"
    container_name       = "crs-central-instance-container"
    key                  = "terraform.tfstate"
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-crs-central-instance-01"  # Following naming convention
  address_space       = ["10.20.27.0/24"]    # New allocated range
  location            = var.location
  resource_group_name = var.resource_group
}

resource "azurerm_subnet" "aks" {
  name         = "snet-aks-crs-central-instance-01"  # Following naming convention
  resource_group_name = var.resource_group
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes   = ["10.20.27.0/25"]  # 128 IPs for AKS
}

# The AKS cluster runs as a service principal (var.aks_sp_client_id), like the Togo envs,
# instead of a system-assigned managed identity. That SP already has Contributor and
# Network Contributor on the subscription, so the cloud provider can join the AKS subnet
# in this VNet when creating LoadBalancer services -- no extra role assignment needed
# (our deployment SP cannot create role assignments).
# If you switch back to a managed identity, the identity needs "Network Contributor" on
# azurerm_subnet.aks, granted by someone with roleAssignments/write:
#   LinkedAuthorizationFailed ... Microsoft.Network/virtualNetworks/subnets/join/action

resource "azurerm_subnet" "postgres" {
  name         = "snet-postgres-crs-central-instance-01"  # Following naming convention
  resource_group_name = var.resource_group
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes   = ["10.20.27.128/26"]  # 64 IPs for PostgreSQL
  service_endpoints  = ["Microsoft.Storage"]

  delegation {
    name = "fs"

    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Create Public IP for Internet Gateway
resource "azurerm_public_ip" "public_ip" {
  name                = "${var.environment}-public-ip"
  resource_group_name = var.resource_group
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create NAT Gateway (optional, for private subnet internet access)
resource "azurerm_nat_gateway" "nat" {
  name                = "${var.environment}-nat-gateway"
  location            = var.location
  resource_group_name = var.resource_group
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "nat_assoc" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.public_ip.id
}

# Associate NAT with private subnet (to give it outbound access)
resource "azurerm_subnet_nat_gateway_association" "nat_private" {
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "db_net_link" {
  name                  = "${var.environment}VnetZone.com"
  private_dns_zone_name = azurerm_private_dns_zone.db.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = var.resource_group
}

resource "azurerm_private_dns_zone" "db" {
  name                = "${var.environment}.postgres.database.azure.com"
  resource_group_name = var.resource_group
}

module "kubernetes" {
  depends_on = [azurerm_nat_gateway_public_ip_association.nat_assoc]
  source                    = "../modules/kubernetes/azure"
  environment               = var.environment
  name                      = var.environment
  location                  = var.location
  resource_group            = var.resource_group
  vm_size                   = "Standard_A4m_v2"
  node_count                = 4
  vnet_subnet_id            = azurerm_subnet.aks.id
  os_disk_size_gb           = 64
  enable_auto_scaling       = false
  min_node_count            = 1
  max_node_count            = 12
  # Enabled on the live cluster (workload identity); keep Terraform in sync so a plan
  # does not try to turn them off.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  # Run the cluster as a service principal (see note above the postgres subnet).
  # Changing this between SP and managed identity recreates the cluster.
  service_principal_client_id     = var.client_id
  service_principal_client_secret = var.client_secret
}

module "postgres-db" {
  source                    = "../modules/db/azure"
  environment               = var.environment
  resource_group            = var.resource_group
  location                  = var.location
  sku_name                  = "GP_Standard_D4ads_v5"
  storage_mb                = "65536"
  backup_retention_days     = "30"
  administrator_login       = var.db_user
  administrator_password    = var.db_password
  db_version                = var.db_version
  db_name                   = "crscentralinstance"
  delegated_subnet_id       = azurerm_subnet.postgres.id
  private_dns_zone_id       = azurerm_private_dns_zone.db.id
  auto_grow_enabled         = true
}