# Getting Started with Gateway API on IONOS Cloud

This guide will walk you through setting up a Kubernetes cluster on IONOS Cloud and running Gateway API tests.

## Prerequisites

Before you begin, ensure you have:

- [ ] An IONOS Cloud account with API access
- [ ] Terraform >= 1.0 installed ([Download](https://www.terraform.io/downloads))
- [ ] kubectl installed ([Install Guide](https://kubernetes.io/docs/tasks/tools/))
- [ ] KUTTL CLI installed ([Install Guide](https://kuttl.dev/docs/cli.html))

## Step 1: Clone the Repository

```bash
git clone https://github.com/Ntr0/gateway-api-examples.git
cd gateway-api-examples
```

## Step 2: Provision the Kubernetes Cluster

### Configure IONOS Cloud Credentials

Export your IONOS Cloud credentials:

```bash
# Option 1: Username and Password
export IONOS_USERNAME="your-username"
export IONOS_PASSWORD="your-password"

# Option 2: API Token (recommended)
export IONOS_TOKEN="your-api-token"
```

To create an API token:
1. Log in to [IONOS Cloud DCD](https://dcd.ionos.com/)
2. Go to Management → Users
3. Create or select a user
4. Generate an API token

### Deploy the Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

When prompted, type `yes` to confirm.

**Expected deployment time:** 10-15 minutes

### Get Cluster Credentials

After the cluster is created, retrieve the kubeconfig:

```bash
# Method 1: Using IONOS Cloud CLI
ionosctl k8s kubeconfig get --cluster-id <cluster-id>

# Method 2: Download from IONOS Cloud DCD
# Navigate to Containers → Managed Kubernetes
# Select your cluster → Download kubeconfig
```

Configure kubectl:

```bash
export KUBECONFIG=/path/to/downloaded/kubeconfig.yaml
```

Verify access:

```bash
kubectl get nodes
```

You should see 3 nodes:
- 1 node from the "loadbalancer" pool
- 2 nodes from the "service" pool

## Step 3: Install Gateway API

Install the Gateway API CRDs:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

Verify installation:

```bash
kubectl get crd | grep gateway
```

## Step 4: Install a Gateway Controller

Choose and install a Gateway API controller. Popular options:

### Option A: Envoy Gateway (Recommended for testing)

```bash
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v0.6.0/install.yaml
```

### Option B: Istio

```bash
# Download Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*/
export PATH=$PWD/bin:$PATH

# Install Istio
istioctl install --set profile=minimal -y
```

### Option C: Kong

```bash
kubectl apply -f https://bit.ly/kong-ingress-gateway
```

Wait for the controller to be ready:

```bash
kubectl wait --for=condition=ready pod -l control-plane=envoy-gateway -n envoy-gateway-system --timeout=300s
```

## Step 5: Run KUTTL Tests

Navigate to the kuttl-tests directory:

```bash
cd ../kuttl-tests
```

### Run All Tests

```bash
kubectl kuttl test
```

### Run Specific Test

```bash
# Basic Gateway test
kubectl kuttl test --test basic-gateway

# Advanced routing test
kubectl kuttl test --test advanced-routing
```

### Run with Verbose Output

```bash
kubectl kuttl test -v 5
```

## Step 6: Explore the Results

After successful test execution, you can examine the created resources:

### Basic Gateway Test

```bash
# View resources
kubectl get gateway,httproute,service,deployment -n gateway-api-test

# Test the application
kubectl port-forward -n gateway-api-test svc/example-app 8080:80
curl http://localhost:8080
```

### Advanced Routing Test

```bash
# View resources
kubectl get gateway,httproute,service,deployment -n advanced-routing-test

# Check weighted routing
kubectl describe httproute weighted-routing -n advanced-routing-test
```

## Cleanup

### Clean up test resources

```bash
# Tests are automatically cleaned up by KUTTL
# To manually clean up:
kubectl delete namespace gateway-api-test advanced-routing-test
```

### Destroy Infrastructure

```bash
cd terraform
terraform destroy
```

When prompted, type `yes` to confirm.

## Troubleshooting

### Issue: Terraform apply fails with authentication error

**Solution:** Verify your IONOS credentials are set correctly:
```bash
echo $IONOS_TOKEN  # or IONOS_USERNAME/IONOS_PASSWORD
```

### Issue: kubectl cannot connect to cluster

**Solution:** Ensure you've downloaded and configured the kubeconfig:
```bash
export KUBECONFIG=/path/to/kubeconfig.yaml
kubectl cluster-info
```

### Issue: Gateway not ready

**Solution:** Check if the Gateway controller is running:
```bash
kubectl get pods -A | grep gateway
kubectl logs -n <controller-namespace> <controller-pod>
```

### Issue: KUTTL tests timeout

**Solution:** Increase timeout in `kuttl-test.yaml`:
```yaml
timeout: 600  # Increase from 300 to 600 seconds
```

### Issue: Nodes not ready

**Solution:** Wait for nodes to fully provision (may take 5-10 minutes):
```bash
kubectl get nodes -w
```

## Next Steps

- Explore the [Terraform configuration](terraform/README.md)
- Review the [KUTTL test documentation](kuttl-tests/README.md)
- Learn more about [Gateway API](https://gateway-api.sigs.k8s.io/)
- Experiment with additional Gateway API features

## Support

For issues specific to:
- **IONOS Cloud:** [IONOS Support](https://www.ionos.com/help)
- **Gateway API:** [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- **This Repository:** [GitHub Issues](https://github.com/Ntr0/gateway-api-examples/issues)
