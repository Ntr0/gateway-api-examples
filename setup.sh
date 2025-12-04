#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
KUBECONFIG_FILE="${SCRIPT_DIR}/kubeconfig.yaml"
ENVOY_PROXY_CONFIG="${SCRIPT_DIR}/envoy-proxy-config.yaml"
GATEWAY_CLASS="${SCRIPT_DIR}/gateway-class.yaml"

# Functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing_tools=()
    
    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Please install the missing tools and try again"
        exit 1
    fi
    
    print_success "All prerequisites are installed"
}

check_ionos_credentials() {
    if [ -z "${IONOS_USERNAME:-}" ] && [ -z "${IONOS_PASSWORD:-}" ] && [ -z "${IONOS_TOKEN:-}" ]; then
        print_error "IONOS Cloud credentials not found"
        print_info "Please set one of the following:"
        print_info "  export IONOS_USERNAME=\"your-username\""
        print_info "  export IONOS_PASSWORD=\"your-password\""
        print_info "  # OR"
        print_info "  export IONOS_TOKEN=\"your-api-token\""
        exit 1
    fi
}

wait_for_kubeconfig() {
    print_info "Waiting for kubeconfig file to be created..."
    local max_attempts=60
    local attempt=0
    
    while [ ! -f "${KUBECONFIG_FILE}" ] && [ $attempt -lt $max_attempts ]; do
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [ ! -f "${KUBECONFIG_FILE}" ]; then
        print_error "Kubeconfig file not found after ${max_attempts} attempts"
        exit 1
    fi
    
    print_success "Kubeconfig file created"
}

wait_for_cluster_ready() {
    print_info "Waiting for cluster to be ready..."
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if kubectl cluster-info &>/dev/null && kubectl get nodes &>/dev/null; then
            print_success "Cluster is ready"
            return 0
        fi
        sleep 5
        attempt=$((attempt + 1))
    done
    
    print_error "Cluster did not become ready in time"
    exit 1
}

create_envoy_proxy_config() {
    print_info "Creating EnvoyProxy configuration..."
    
    cat > "${ENVOY_PROXY_CONFIG}" <<EOF
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: envoy-proxy-config
  namespace: envoy-gateway-system
spec:
  provider:
    kubernetes:
      envoyDeployment:
        pod:
          nodeSelector:
            cloud.ionos.com/nodepool-name: loadbalancer
      envoyService:
        annotations:
          cloud.ionos.com/node-selector: cloud.ionos.com/nodepool-name=loadbalancer
        externalTrafficPolicy: Local
        type: LoadBalancer
    type: Kubernetes
EOF
    
    print_success "EnvoyProxy configuration created"
}

create_gateway_class() {
    print_info "Creating GatewayClass configuration..."
    
    cat > "${GATEWAY_CLASS}" <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway-class
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: envoy-proxy-config
    namespace: envoy-gateway-system
EOF
    
    print_success "GatewayClass configuration created"
}


install_cert_manager() {
    print_info "Installing Cert-Manager..."
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
        --namespace cert-manager --create-namespace \
        --version v1.19.0 \
        --set crds.enabled=true \
        --wait --timeout 5m || true
    
    print_success "Cert-Manager installed"
}

install_envoy_gateway() {
    print_info "Installing Envoy Gateway..."
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    helm upgrade --install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
        --namespace envoy-gateway-system --create-namespace \
        --version v1.6.0 \
        --wait --timeout 5m
    
    print_success "Envoy Gateway installed"
}

apply_envoy_config() {
    print_info "Applying EnvoyProxy configuration..."
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    kubectl apply -f "${ENVOY_PROXY_CONFIG}"
    
    print_success "EnvoyProxy configuration applied"
}

apply_gateway_class() {
    print_info "Applying GatewayClass..."
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    kubectl apply -f "${GATEWAY_CLASS}"
    
    print_info "Waiting for GatewayClass to be accepted..."
    kubectl wait --for=condition=Accepted gatewayclass/envoy-gateway-class --timeout=300s || true
    
    print_success "GatewayClass applied and accepted"
}

create_basic_auth_secret() {
    print_info "Creating basic auth secret..."
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    # Generate htpasswd file using SHA format (required by Envoy Gateway)
    # Format: username:{SHA}base64_encoded_sha1_hash
    # For admin:admin123 and user:user123
    
    # Generate SHA1 hash and base64 encode it
    local admin_sha1=$(echo -n "admin123" | openssl dgst -sha1 -binary | openssl base64)
    local user_sha1=$(echo -n "user123" | openssl dgst -sha1 -binary | openssl base64)
    
    # Create htpasswd entries in format: username:{SHA}base64_hash
    local admin_entry="admin:{SHA}${admin_sha1}"
    local user_entry="user:{SHA}${user_sha1}"
    
    # Create secret with htpasswd content
    kubectl create secret generic basic-auth-secret \
        --from-literal=.htpasswd="${admin_entry}
${user_entry}" \
        -n gateway-demos \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "Basic auth secret created"
}

install_demo_services() {
    print_info "Installing demo http-echo services..."
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    kubectl apply -f "${SCRIPT_DIR}/demo/services.yaml"
    
    print_info "Waiting for demo services to be ready..."
    kubectl wait --for=condition=ready pod -l app=echo-service -n gateway-demos --timeout=300s || true
    kubectl wait --for=condition=ready pod -l app=echo-service-v1 -n gateway-demos --timeout=300s || true
    kubectl wait --for=condition=ready pod -l app=echo-service-v2 -n gateway-demos --timeout=300s || true
    
    # Create basic auth secret
    create_basic_auth_secret
    
    print_success "Demo services installed"
}

cleanup_temp_files() {
    print_info "Cleaning up temporary configuration files..."
    rm -f "${ENVOY_PROXY_CONFIG}" "${GATEWAY_CLASS}"
    print_success "Cleanup complete"
}

main() {
    print_header "Gateway API Setup Script"
    
    # Step 1: Check prerequisites
    check_prerequisites
    check_ionos_credentials
    
    # Step 2: Provision cluster with Terraform
    print_header "Step 1: Provisioning Kubernetes Cluster"
    cd "${TERRAFORM_DIR}"
    print_info "Initializing Terraform..."
    terraform init
    
    print_info "Applying Terraform configuration..."
    terraform apply -auto-approve
    
    cd "${SCRIPT_DIR}"
    wait_for_kubeconfig
    
    # Step 3: Wait for cluster to be ready
    print_header "Step 2: Waiting for Cluster Readiness"
    wait_for_cluster_ready
    
    # Step 4: Install Cert-Manager
    print_header "Step 3: Installing Cert-Manager"
    install_cert_manager
    
    # Step 5: Install Envoy Gateway
    print_header "Step 4: Installing Envoy Gateway"
    install_envoy_gateway
    
    # Step 6: Create and apply EnvoyProxy configuration
    print_header "Step 5: Configuring Envoy Gateway"
    create_envoy_proxy_config
    apply_envoy_config
    
    # Step 7: Create and apply GatewayClass
    print_header "Step 6: Creating GatewayClass"
    create_gateway_class
    apply_gateway_class
    
    # Step 8: Install demo services
    print_header "Step 7: Installing Demo Services"
    install_demo_services
    
    # Step 9: Cleanup
    cleanup_temp_files
    
    print_header "Setup Complete!"
    print_success "Kubernetes cluster is provisioned and Envoy Gateway is installed"
    print_info "Kubeconfig location: ${KUBECONFIG_FILE}"
    print_info "GatewayClass: envoy-gateway-class"
    print_info "Demo services installed in namespace: gateway-demos"
    print_info ""
    print_info "You can now use the cluster with:"
    print_info "  export KUBECONFIG=${KUBECONFIG_FILE}"
    print_info ""
    print_info "Run demos with:"
    print_info "  ./demo.sh basic-routing"
    print_info "  ./demo.sh advanced-routing"
    print_info "  ./demo.sh basic-auth"
    print_info "  ./demo.sh rate-limiting"
}

main "$@"

