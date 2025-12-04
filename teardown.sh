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
DEMO_SCRIPT="${SCRIPT_DIR}/demo.sh"
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

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

check_kubeconfig() {
    if [ ! -f "${KUBECONFIG_FILE}" ]; then
        print_error "Kubeconfig file not found: ${KUBECONFIG_FILE}"
        print_info "Cluster may already be destroyed or was never created"
        return 1
    fi
    return 0
}

cleanup_demos() {
    print_header "Cleaning up Demo Resources"
    
    if [ ! -f "${DEMO_SCRIPT}" ]; then
        print_warning "Demo script not found, skipping demo cleanup"
        return
    fi
    
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    # Cleanup all demo resources
    print_info "Cleaning up all demo resources..."
    "${DEMO_SCRIPT}" --cleanup all 2>/dev/null || print_warning "Some demo resources may not exist"
    
    # Cleanup demo services and namespace
    print_info "Cleaning up demo services and namespace..."
    "${DEMO_SCRIPT}" --cleanup services 2>/dev/null || print_warning "Demo services may not exist"
    
    print_success "Demo resources cleaned up"
}

cleanup_gateway_resources() {
    print_header "Cleaning up Gateway Resources"
    
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    # Delete GatewayClass
    print_info "Deleting GatewayClass..."
    kubectl delete gatewayclass envoy-gateway-class --ignore-not-found=true || true
    
    # Delete EnvoyProxy configuration
    print_info "Deleting EnvoyProxy configuration..."
    kubectl delete envoyproxy envoy-proxy-config -n envoy-gateway-system --ignore-not-found=true || true
    
    print_success "Gateway resources cleaned up"
}

cleanup_helm_releases() {
    print_header "Cleaning up Helm Releases"
    
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    # Uninstall Envoy Gateway
    print_info "Uninstalling Envoy Gateway..."
    helm uninstall envoy-gateway -n envoy-gateway-system --ignore-not-found=true || true
    
    # Wait for namespace to be deletable
    print_info "Waiting for Envoy Gateway namespace to be ready for deletion..."
    sleep 5
    
    # Delete Envoy Gateway namespace
    print_info "Deleting envoy-gateway-system namespace..."
    kubectl delete namespace envoy-gateway-system --ignore-not-found=true --wait=true --timeout=60s || true
    
    # Uninstall Cert-Manager
    print_info "Uninstalling Cert-Manager..."
    helm uninstall cert-manager -n cert-manager --ignore-not-found=true || true
    
    # Wait for namespace to be deletable
    print_info "Waiting for Cert-Manager namespace to be ready for deletion..."
    sleep 5
    
    # Delete Cert-Manager namespace
    print_info "Deleting cert-manager namespace..."
    kubectl delete namespace cert-manager --ignore-not-found=true --wait=true --timeout=60s || true
    
    print_success "Helm releases cleaned up"
}

cleanup_temp_files() {
    print_info "Cleaning up temporary configuration files..."
    rm -f "${ENVOY_PROXY_CONFIG}" "${GATEWAY_CLASS}"
    print_success "Temporary files cleaned up"
}

destroy_terraform() {
    print_header "Destroying Terraform Infrastructure"
    
    if [ ! -d "${TERRAFORM_DIR}" ]; then
        print_error "Terraform directory not found: ${TERRAFORM_DIR}"
        return 1
    fi
    
    cd "${TERRAFORM_DIR}"
    
    print_warning "This will destroy the Kubernetes cluster and all associated resources!"
    print_info "Destroying Terraform infrastructure..."
    
    terraform destroy -auto-approve
    
    cd "${SCRIPT_DIR}"
    
    # Remove kubeconfig file after cluster is destroyed
    if [ -f "${KUBECONFIG_FILE}" ]; then
        print_info "Removing kubeconfig file..."
        rm -f "${KUBECONFIG_FILE}"
    fi
    
    print_success "Terraform infrastructure destroyed"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Teardown script to clean up Gateway API demo resources.

OPTIONS:
    -h, --help              Show this help message
    -k, --keep-cluster      Keep the Kubernetes cluster (only remove Kubernetes resources)
    -f, --force             Skip confirmation prompts
    --kubeconfig-only       Only remove Kubernetes resources (same as --keep-cluster)

By default, this script will:
  1. Clean up all demo resources
  2. Remove GatewayClass and EnvoyProxy configuration
  3. Uninstall Envoy Gateway and Cert-Manager Helm releases
  4. Destroy the Terraform infrastructure (unless --keep-cluster is used)

Examples:
    $0                      # Full teardown including cluster destruction
    $0 --keep-cluster       # Keep cluster, only remove Kubernetes resources
    $0 --force              # Skip confirmation prompts
EOF
}

confirm_destroy() {
    if [ "${FORCE:-false}" = "true" ]; then
        return 0
    fi
    
    echo ""
    print_warning "This will destroy all resources including the Kubernetes cluster!"
    echo -n "Are you sure you want to continue? (yes/no): "
    read -r response
    
    case "$response" in
        yes|y|YES|Y)
            return 0
            ;;
        *)
            print_info "Teardown cancelled"
            exit 0
            ;;
    esac
}

main() {
    local keep_cluster=false
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -k|--keep-cluster|--kubeconfig-only)
                keep_cluster=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    export FORCE="${force}"
    
    print_header "Gateway API Teardown Script"
    
    # Check if kubeconfig exists
    if ! check_kubeconfig; then
        if [ "${keep_cluster}" = "false" ]; then
            print_info "Attempting to destroy Terraform infrastructure anyway..."
            destroy_terraform
        else
            print_info "Kubeconfig not found and --keep-cluster specified, nothing to do"
            exit 0
        fi
        exit 0
    fi
    
    # Confirm destruction unless force is set
    if [ "${keep_cluster}" = "false" ]; then
        confirm_destroy
    fi
    
    # If destroying cluster, skip Kubernetes resource cleanup (waste of time)
    if [ "${keep_cluster}" = "false" ]; then
        print_info "Skipping Kubernetes resource cleanup (cluster will be destroyed)"
        
        # Step 1: Cleanup temp files only
        cleanup_temp_files
        
        # Step 2: Destroy Terraform infrastructure
        destroy_terraform
        print_header "Teardown Complete!"
        print_success "All resources have been destroyed"
    else
        # Keep cluster, so clean up Kubernetes resources
        # Step 1: Cleanup demo resources
        cleanup_demos
        
        # Step 2: Cleanup gateway resources
        cleanup_gateway_resources
        
        # Step 3: Cleanup Helm releases
        cleanup_helm_releases
        
        # Step 4: Cleanup temp files
        cleanup_temp_files
        
        print_header "Teardown Complete!"
        print_success "Kubernetes resources have been removed"
        print_info "Kubernetes cluster is still running"
        print_info "Kubeconfig location: ${KUBECONFIG_FILE}"
        print_info ""
        print_info "To destroy the cluster, run:"
        print_info "  cd ${TERRAFORM_DIR} && terraform destroy"
    fi
}

main "$@"

