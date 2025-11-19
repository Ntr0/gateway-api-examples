# Terraform Configuration for IONOS Cloud Kubernetes Cluster

This Terraform configuration creates a Kubernetes cluster on IONOS Cloud with two node pools for Gateway API examples.

## Prerequisites

1. Terraform >= 1.0
2. IONOS Cloud account
3. IONOS Cloud credentials

## Cluster Configuration

The configuration creates:
- **Kubernetes Cluster**: A managed Kubernetes cluster on IONOS Cloud
- **Node Pool "loadbalancer"**: 1 node with 2 CPUs and 4 GB RAM
- **Node Pool "service"**: 2 nodes with 2 CPUs and 4 GB RAM (auto-scaling to max 3 nodes)

## Authentication

Set one of the following environment variables for authentication:

```bash
# Option 1: Username and Password
export IONOS_USERNAME="your-username"
export IONOS_PASSWORD="your-password"

# Option 2: API Token
export IONOS_TOKEN="your-api-token"
```

## Usage

1. Initialize Terraform:
```bash
cd terraform
terraform init
```

2. Review the execution plan:
```bash
terraform plan
```

3. Apply the configuration:
```bash
terraform apply
```

4. Get the kubeconfig:
```bash
# After the cluster is created, you can retrieve the kubeconfig
# using the IONOS Cloud CLI or web console
```

5. Destroy resources when done:
```bash
terraform destroy
```

## Customization

You can customize the configuration by creating a `terraform.tfvars` file:

```hcl
cluster_name      = "my-gateway-cluster"
k8s_version       = "1.28.2"
location          = "de/txl"
storage_size      = 100
```

## Outputs

After successful deployment, the following outputs are available:
- `cluster_id`: ID of the Kubernetes cluster
- `cluster_name`: Name of the cluster
- `k8s_version`: Kubernetes version
- `datacenter_id`: Datacenter ID
- `loadbalancer_node_pool_id`: ID of the loadbalancer node pool
- `service_node_pool_id`: ID of the service node pool
