# gateway-api-examples

Examples and infrastructure for demonstrating Kubernetes Gateway API functionality on IONOS Cloud.

## Overview

This repository contains:

1. **Terraform Configuration** (`terraform/`): Infrastructure-as-Code to provision a Kubernetes cluster on IONOS Cloud
2. **KUTTL Tests** (`kuttl-tests/`): Automated tests for Gateway API resources and functionality

## Quick Start

**→ See [GETTING_STARTED.md](GETTING_STARTED.md) for a detailed step-by-step guide.**

### 1. Provision Infrastructure

Create a Kubernetes cluster on IONOS Cloud with two node pools:

```bash
cd terraform

# Configure authentication
export IONOS_USERNAME="your-username"
export IONOS_PASSWORD="your-password"

# Initialize and apply
terraform init
terraform apply
```

**Cluster Configuration:**
- **Node Pool "loadbalancer"**: 1 node, 2 CPUs, 4 GB RAM
- **Node Pool "service"**: 2 nodes, 2 CPUs, 4 GB RAM

See [`terraform/README.md`](terraform/README.md) for detailed instructions.

### 2. Run Gateway API Tests

Test Gateway API functionality with KUTTL:

```bash
# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Install a Gateway controller (e.g., Envoy Gateway, Istio, Kong)

# Run tests
cd kuttl-tests
kubectl kuttl test
```

See [`kuttl-tests/README.md`](kuttl-tests/README.md) for detailed test documentation.

## Components

### Terraform Infrastructure

The Terraform configuration creates:
- Managed Kubernetes cluster on IONOS Cloud
- Two node pools optimized for different workloads
- Configurable cluster settings (version, location, storage)

### KUTTL Tests

The test suite includes:
- **Basic Gateway Tests**: Fundamental Gateway API concepts
- **Advanced Routing Tests**: Path-based, header-based, and weighted routing

## Prerequisites

- IONOS Cloud account
- Terraform >= 1.0
- kubectl
- KUTTL CLI

## Repository Structure

```
.
├── terraform/           # Infrastructure as Code for IONOS Cloud
│   ├── main.tf         # Main Terraform configuration
│   ├── variables.tf    # Input variables
│   ├── outputs.tf      # Output values
│   └── README.md       # Terraform documentation
└── kuttl-tests/        # Gateway API tests
    ├── kuttl-test.yaml # Test suite configuration
    ├── tests/          # Test cases
    └── README.md       # Test documentation
```

## License

See [LICENSE](LICENSE) file for details.
