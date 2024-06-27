variable "location" {
  description = "Location"
}

variable "resource_group" {
  description = "Name of the Resource Group"
}

variable "cluster_name" {
  description = "Name of the Cluster"
}

variable "node_pool_name" {
  description = "Name of the Node Pool"
}

variable "vm_size" {
  description = "Size of the Node Pool VMs"
  default = "Standard_DS2_v2"
}

variable "node_count" {
  default     = 2
  description = "Node count for the Node Pool"
}