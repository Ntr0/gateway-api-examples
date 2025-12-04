# gateway-api-examples

Examples and infrastructure for demonstrating Kubernetes Gateway API functionality on IONOS Cloud.

## Overview

This repository contains:

1. **Setup Scripts** (`setup.sh`, `teardown.sh`, `demo.sh`): Main entrypoints for cluster provisioning, cleanup, and running demos
2. **Demo Examples** (`demo/`): Gateway API demo configurations (basic routing, advanced routing, basic auth, rate limiting, TLS)
3. **Terraform Configuration** (`terraform/`): Infrastructure-as-Code to provision a Kubernetes cluster on IONOS Cloud

## Quick Start

**→ See [GETTING_STARTED.md](GETTING_STARTED.md) for a detailed step-by-step guide.**

### 1. Setup Cluster and Gateway

Run the setup script to provision the cluster and install Envoy Gateway:

```bash
# Configure authentication
export IONOS_USERNAME="your-username"
export IONOS_PASSWORD="your-password"

# Run setup (provisions cluster, installs cert-manager, Envoy Gateway, and demo services)
./setup.sh
```

**Cluster Configuration:**
- **Node Pool "loadbalancer"**: 1 node, 2 CPUs, 4 GB RAM
- **Node Pool "service"**: 2 nodes, 2 CPUs, 4 GB RAM

### 2. Run Demos

Run Gateway API demos:

```bash
# List available demos
./demo.sh --list

# Run a specific demo
./demo.sh basic-routing
./demo.sh advanced-routing
./demo.sh basic-auth
./demo.sh rate-limiting
./demo.sh tls

# Run all demos
./demo.sh all
```

## Components

### Terraform Infrastructure

The Terraform configuration creates:
- Managed Kubernetes cluster on IONOS Cloud
- Two node pools optimized for different workloads
- Configurable cluster settings (version, location, storage)

## Prerequisites

- IONOS Cloud account
- Terraform >= 1.0
- kubectl
- helm
- curl

## Repository Structure

```
.
├── setup.sh            # Main setup script (provisions cluster, installs Gateway)
├── teardown.sh         # Teardown script (cleans up resources)
├── demo.sh             # Demo runner script
├── demo/               # Gateway API demo configurations
│   ├── basic-routing/  # Basic HTTP routing demo
│   ├── advanced-routing/ # Weighted load balancing demo
│   ├── basic-auth/     # Basic authentication demo
│   ├── rate-limiting/  # Rate limiting demo
│   ├── tls/            # TLS/HTTPS termination demo
│   └── services.yaml   # Demo backend services
└── terraform/          # Infrastructure as Code for IONOS Cloud
    ├── main.tf         # Main Terraform configuration
    ├── variables.tf    # Input variables
    ├── outputs.tf      # Output values
    └── README.md       # Terraform documentation
```

## Teardown

To clean up all resources, use the teardown script:

```bash
# Full teardown (destroys cluster and all resources)
./teardown.sh

# Keep cluster, only remove Kubernetes resources
./teardown.sh --keep-cluster

# Skip confirmation prompts
./teardown.sh --force
```

The teardown script will:
1. Clean up all demo resources
2. Remove GatewayClass and EnvoyProxy configuration
3. Uninstall Envoy Gateway and Cert-Manager Helm releases
4. Optionally destroy the Terraform infrastructure (unless `--keep-cluster` is used)

## License

See [LICENSE](LICENSE) file for details.
