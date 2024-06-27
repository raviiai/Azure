############################
## Resource Group
############################

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group
  location = var.location
}

#############################
## Creating VNet
#############################

resource "azurerm_virtual_network" "vnet" {
  name                = "aks-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

#############################
## Creating Subnets
#############################

resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  resource_group_name  = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "netapp_subnet" {
  resource_group_name  = azurerm_resource_group.rg.name
  address_prefixes     = ["10.0.2.0/24"]
  name                 = "netapp-subnet"
  virtual_network_name = azurerm_virtual_network.vnet.name

  delegation {
    name = "service-delegation-netApp"
    
    service_delegation {
      name    = "Microsoft.Netapp/volumes"
      actions = [
        "Microsoft.Network/networkInterfaces/*",
        "Microsoft.Network/virtualNetworks/subnet/join/action"
      ]
    }
  }
}

#############################
## Network Security Group
#############################

resource "azurerm_network_security_group" "aks_nsg" {
  name                = "aks-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowNetAppTraffic"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2049"
    source_address_prefix      = "10.0.2.0/24"
    destination_address_prefix = "10.0.1.0/24"
  }
}

resource "azurerm_subnet_network_security_group_association" "aks_subnet_nsg_assoc" {
  subnet_id                 = azurerm_subnet.aks_subnet.id
  network_security_group_id = azurerm_network_security_group.aks_nsg.id
}

#############################
## AKS Cluster
#############################

resource "azurerm_kubernetes_cluster" "cluster" {
  name                = var.cluster_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  dns_prefix          = "aks-cluster"
  
  default_node_pool {
    name       = var.node_pool_name
    vm_size    = var.vm_size
    node_count = var.node_count
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "Standard"
  }

  tags = {
    AppOwner = "Ravi"
  }
}

##########################
## NetApp
##########################

resource "azurerm_netapp_account" "netapp_account" {
  name                = "myNetAppAccount"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  active_directory {
    username       = "netapp"
    password       = "netapp"
    domain         = "netapp.test"
    dns_servers    = ["10.0.4.3"]
    smb_server_name = "ANFSMB"
  }
}

resource "azurerm_netapp_pool" "netapp_pool" {
  name                 = "myNetAppPool"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  account_name         = azurerm_netapp_account.netapp_account.name
  service_level        = "Premium"
  size_in_tb           = 4
}

resource "azurerm_netapp_volume" "netapp_volume" {
  name                 = "netapp-volume"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  account_name         = azurerm_netapp_account.netapp_account.name
  pool_name            = azurerm_netapp_pool.netapp_pool.name
  volume_path          = "myNetAppVolume"
  service_level        = "Premium"
  subnet_id            = azurerm_subnet.netapp_subnet.id
  storage_quota_in_gb  = 100
  protocols            = ["CIFS"]

  lifecycle {
    prevent_destroy = true
  }
}

###############################
## Private Endpoint for NetApp
###############################

resource "azurerm_private_endpoint" "netapp_private_endpoint" {
  name                = "myNetAppPrivateEndpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.netapp_subnet.id

  private_service_connection {
    name                           = "myNetAppConnection"
    private_connection_resource_id = azurerm_netapp_volume.netapp_volume.id
    is_manual_connection           = false
    subresource_names              = ["file"]
  }
}

###########################
## Private DNS Zone
###########################

resource "azurerm_private_dns_zone" "dns_zone" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns_link" {
  name                  = "myDNSLink"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_a_record" "dns_record" {
  name                = "myNetAppRecord"
  zone_name           = azurerm_private_dns_zone.dns_zone.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.netapp_private_endpoint.private_ip_address]
}
