terraform {
  required_providers {
    ionoscloud = {
      source  = "ionos-cloud/ionoscloud"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.0"
}

provider "ionoscloud" {
  # Authentication will be provided via environment variables:
  # IONOS_USERNAME and IONOS_PASSWORD
  # or IONOS_TOKEN
}

resource "ionoscloud_datacenter" "dc" {
  location = var.location
  name = "gateway_api_demo"
}

resource "ionoscloud_k8s_cluster" "gateway_api_cluster" {
  name        = var.cluster_name
  k8s_version = var.k8s_version
//  location    = var.location
  
  maintenance_window {
    day_of_the_week = "Sunday"
    time            = "03:00:00Z"
  }
}

resource "ionoscloud_k8s_node_pool" "loadbalancer" {
  datacenter_id  = ionoscloud_datacenter.dc.id
  k8s_cluster_id = ionoscloud_k8s_cluster.gateway_api_cluster.id
  name           = "loadbalancer"
  k8s_version    = ionoscloud_k8s_cluster.gateway_api_cluster.k8s_version

  server_type = var.serverType
  availability_zone = var.availability_zone
  storage_type      = var.storage_type
  node_count        = 1
  cores_count       = 2
  ram_size          = 4096
  storage_size      = var.storage_size
  
  maintenance_window {
    day_of_the_week = "Sunday"
    time            = "03:00:00Z"
  }
  
  labels = {
    role = "loadbalancer"
  }
  annotations = {}
  
  lifecycle {
    ignore_changes = [annotations]
  }
}

resource "ionoscloud_k8s_node_pool" "service" {
  datacenter_id  = ionoscloud_datacenter.dc.id
  k8s_cluster_id = ionoscloud_k8s_cluster.gateway_api_cluster.id
  name           = "service"
  k8s_version    = ionoscloud_k8s_cluster.gateway_api_cluster.k8s_version

  server_type = var.serverType
  availability_zone = var.availability_zone
  storage_type      = var.storage_type
  node_count        = 2
  cores_count       = 2
  ram_size          = 4096
  storage_size      = var.storage_size
  
  maintenance_window {
    day_of_the_week = "Sunday"
    time            = "03:00:00Z"
  }
  
  labels = {
    role = "service"
  }
  annotations = {}
  
  lifecycle {
    ignore_changes = [annotations]
  }
}

data "ionoscloud_k8s_cluster" demo {
  id = ionoscloud_k8s_cluster.gateway_api_cluster.id
}

resource "local_sensitive_file" "kube_config" {
  filename = "../kubeconfig.yaml"
  content = data.ionoscloud_k8s_cluster.demo.kube_config
}