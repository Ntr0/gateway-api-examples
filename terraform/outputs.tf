output "cluster_id" {
  description = "ID of the created Kubernetes cluster"
  value       = ionoscloud_k8s_cluster.gateway_api_cluster.id
}

output "cluster_name" {
  description = "Name of the created Kubernetes cluster"
  value       = ionoscloud_k8s_cluster.gateway_api_cluster.name
}

output "k8s_version" {
  description = "Kubernetes version of the cluster"
  value       = ionoscloud_k8s_cluster.gateway_api_cluster.k8s_version
}

output "datacenter_id" {
  description = "Datacenter ID where the cluster is created"
  value       = ionoscloud_k8s_cluster.gateway_api_cluster.datacenter_id
}

output "loadbalancer_node_pool_id" {
  description = "ID of the loadbalancer node pool"
  value       = ionoscloud_k8s_node_pool.loadbalancer.id
}

output "service_node_pool_id" {
  description = "ID of the service node pool"
  value       = ionoscloud_k8s_node_pool.service.id
}
