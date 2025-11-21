# KUTTL Tests for Gateway API

This directory contains KUTTL (KUbernetes Test TooL) tests for validating Gateway API resources and functionality.

## Prerequisites

1. Kubernetes cluster (can be created using the Terraform configuration in the `terraform/` directory)
2. Gateway API CRDs installed:
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
   ```
3. KUTTL CLI installed:
   ```bash
   # Using krew
   kubectl krew install kuttl
   
   # Or download directly
   # https://github.com/kudobuilder/kuttl/releases
   ```
4. A Gateway API controller (e.g., Envoy Gateway, Istio, Kong, etc.)

## Test Structure

### Test Suite 1: Basic Gateway (`tests/basic-gateway/`)
Tests fundamental Gateway API concepts:
- Namespace creation
- GatewayClass definition
- Gateway resource creation
- Simple application deployment
- Basic HTTPRoute configuration

**Resources tested:**
- GatewayClass
- Gateway with HTTP listener
- HTTPRoute with simple path-based routing
- Sample application (2 replicas)

### Test Suite 2: Advanced Routing (`tests/advanced-routing/`)
Tests advanced Gateway API routing features:
- Multiple backend services
- Path-based routing
- Header-based routing
- Weighted traffic splitting (canary deployments)
- HTTPS listener configuration

**Resources tested:**
- GatewayClass
- Gateway with HTTP and HTTPS listeners
- HTTPRoute with path-based routing (/v1, /v2)
- HTTPRoute with header-based routing
- HTTPRoute with weighted backends (80/20 split)
- Multiple backend deployments

## Running the Tests

### Run all tests:
```bash
cd kuttl-tests
kubectl kuttl test
```

### Run a specific test:
```bash
cd kuttl-tests
kubectl kuttl test --test basic-gateway
```

### Run with verbose output:
```bash
kubectl kuttl test --config kuttl-test.yaml -v 5
```

## Test Workflow

Each test follows this pattern:

1. **Setup (00-*.yaml)**: Creates namespace, GatewayClass, and Gateway
2. **Resource Creation (01-*.yaml, 02-*.yaml, etc.)**: Deploys applications and routes
3. **Assertions (*-assert.yaml)**: Verifies resources are created correctly
4. **Cleanup**: KUTTL automatically cleans up resources after tests

## Configuration

The `kuttl-test.yaml` file contains the test suite configuration:
- Test directories to run
- Timeout settings (300 seconds)
- Whether to skip cleanup
- Whether to start a control plane

## Expected Results

All tests should pass if:
- Gateway API CRDs are installed
- A Gateway API controller is running
- The cluster has sufficient resources
- Network policies allow the required traffic

## Troubleshooting

### Tests timeout
- Increase the timeout in `kuttl-test.yaml`
- Check if the Gateway controller is running properly
- Verify pods are being scheduled and starting

### Gateway not ready
- Ensure a Gateway API controller is installed
- Check controller logs for errors
- Verify the GatewayClass is accepted by the controller

### Routes not working
- Verify the Gateway is programmed and ready
- Check HTTPRoute status conditions
- Ensure backend services are ready and healthy

## Extending the Tests

To add new tests:

1. Create a new directory under `tests/`
2. Add numbered YAML files for resources (00-*, 01-*, etc.)
3. Add corresponding assertion files (*-assert.yaml)
4. Update this README with test description

## Integration with CI/CD

These tests can be integrated into CI/CD pipelines:

```bash
# Example CI script
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
# Install your Gateway controller
kubectl apply -f your-gateway-controller.yaml
# Wait for controller to be ready
kubectl wait --for=condition=ready pod -l app=gateway-controller -n gateway-system --timeout=300s
# Run KUTTL tests
kubectl kuttl test --config kuttl-tests/kuttl-test.yaml
```
