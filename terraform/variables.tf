variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "gateway-api-cluster"
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = ""
}

variable "location" {
  description = "Location/region for the cluster"
  type        = string
  default     = "de/txl"
}

variable "serverType" {
  description = "CPU family for nodes"
  type        = string
  default     = "VCPU"
}

variable "availability_zone" {
  description = "Availability zone"
  type        = string
  default     = "AUTO"
}

variable "storage_type" {
  description = "Storage type for nodes"
  type        = string
  default     = "SSD"
}

variable "storage_size" {
  description = "Storage size in GB for each node"
  type        = number
  default     = 20
}
