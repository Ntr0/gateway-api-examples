#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXAMPLES_DIR="${REPO_ROOT}/examples"
WAIT_TIMEOUT=300
DEMO_NAMESPACE_PREFIX="gateway-api-demo"

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

print_step() {
    echo -e "${CYAN}→ $1${NC}"
}

wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local condition=${4:-ready}
    
    print_info "Waiting for ${resource_type}/${resource_name} in namespace ${namespace}..."
    
    if kubectl wait --for=condition=${condition} ${resource_type}/${resource_name} -n ${namespace} --timeout=${WAIT_TIMEOUT}s 2>/dev/null; then
        print_success "${resource_type}/${resource_name} is ${condition}"
        return 0
    else
        print_error "${resource_type}/${resource_name} did not become ${condition} within ${WAIT_TIMEOUT}s"
        return 1
    fi
}

wait_for_pods() {
    local namespace=$1
    local selector=${2:-""}
    
    print_info "Waiting for pods in namespace ${namespace}..."
    
    local cmd="kubectl wait --for=condition=ready pod"
    if [ -n "$selector" ]; then
        cmd="${cmd} -l ${selector}"
    fi
    cmd="${cmd} -n ${namespace} --timeout=${WAIT_TIMEOUT}s"
    
    if eval ${cmd} 2>/dev/null; then
        print_success "Pods in ${namespace} are ready"
        return 0
    else
        print_error "Pods in ${namespace} did not become ready within ${WAIT_TIMEOUT}s"
        return 1
    fi
}

get_gateway_address() {
    local gateway_name=$1
    local namespace=$2
    
    print_info "Getting Gateway address for ${gateway_name}..."
    
    local address=""
    local max_attempts=30
    local attempt=0
    
    while [ -z "$address" ] && [ $attempt -lt $max_attempts ]; do
        # Try Gateway status first
        address=$(kubectl get gateway ${gateway_name} -n ${namespace} -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
        
        if [ -z "$address" ]; then
            # Fallback: try to get LoadBalancer service IP
            address=$(kubectl get svc -n ${namespace} -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [ -z "$address" ]; then
                address=$(kubectl get svc -n ${namespace} -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
            fi
        fi
        
        if [ -z "$address" ]; then
            sleep 2
            attempt=$((attempt + 1))
        fi
    done
    
    echo "$address"
}

deploy_example() {
    local example_name=$1
    local example_dir="${EXAMPLES_DIR}/${example_name}"
    
    if [ ! -d "$example_dir" ]; then
        print_error "Example directory not found: ${example_dir}"
        return 1
    fi
    
    print_header "Deploying ${example_name} example"
    
    # Apply all YAML files in the directory
    print_step "Applying resources from ${example_dir}..."
    kubectl apply -f "${example_dir}/" || {
        print_error "Failed to apply resources from ${example_dir}"
        return 1
    }
    
    # Wait for namespace to be active
    # Try to find namespace from Namespace resource or from metadata
    local namespace=$(grep -h "^kind: Namespace" -A 5 ${example_dir}/*.yaml 2>/dev/null | grep -m1 "name:" | awk '{print $2}' | tr -d '"' || echo "")
    
    if [ -z "$namespace" ]; then
        # Try to find namespace from metadata in any resource
        namespace=$(grep -h "namespace:" ${example_dir}/*.yaml 2>/dev/null | grep -v "^#" | head -1 | awk '{print $2}' | tr -d '"' || echo "")
    fi
    
    if [ -z "$namespace" ]; then
        print_error "Could not determine namespace from example files"
        return 1
    fi
    
    print_info "Waiting for namespace ${namespace}..."
    kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/${namespace} --timeout=30s 2>/dev/null || true
    
    # Wait for Gateway to be ready (if exists)
    local gateway_name=$(grep -h "kind: Gateway" -A 5 ${example_dir}/*.yaml 2>/dev/null | grep "name:" | head -1 | awk '{print $2}' | tr -d '"' || echo "")
    if [ -n "$gateway_name" ]; then
        print_info "Waiting for Gateway ${gateway_name} to be programmed..."
        # Wait for Gateway to be accepted and programmed
        local max_wait=60
        local waited=0
        while [ $waited -lt $max_wait ]; do
            local status=$(kubectl get gateway ${gateway_name} -n ${namespace} -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
            if [ "$status" = "True" ]; then
                print_success "Gateway ${gateway_name} is programmed"
                break
            fi
            sleep 2
            waited=$((waited + 2))
        done
    fi
    
    # Wait for pods
    wait_for_pods "${namespace}" || print_info "Some pods may still be starting..."
    
    print_success "${example_name} example deployed to namespace ${namespace}"
    echo "$namespace"
}

test_basic_gateway() {
    local namespace=$1
    local gateway_name="example-gateway"
    local address=$(get_gateway_address "${gateway_name}" "${namespace}")
    
    if [ -z "$address" ]; then
        print_error "Could not get Gateway address. The Gateway may not have an external IP yet."
        print_info "You can check the Gateway status with: kubectl get gateway ${gateway_name} -n ${namespace}"
        return 1
    fi
    
    print_header "Testing Basic Gateway Example"
    print_info "Gateway address: ${address}"
    
    echo -e "\n${CYAN}Making requests to http://${address}/${NC}"
    for i in {1..5}; do
        response=$(curl -s -w "\nHTTP Status: %{http_code}" -H "Host: example.com" "http://${address}/" 2>&1 || echo "Failed")
        http_code=$(echo "$response" | grep "HTTP Status" | awk '{print $3}')
        body=$(echo "$response" | grep -v "HTTP Status")
        if [ "$http_code" = "200" ]; then
            echo -e "${GREEN}Request $i: Success (200)${NC} - $body"
        else
            echo -e "${YELLOW}Request $i: HTTP $http_code${NC} - $body"
        fi
        sleep 1
    done
}

test_advanced_routing() {
    local namespace=$1
    local gateway_name="advanced-gateway"
    local address=$(get_gateway_address "${gateway_name}" "${namespace}")
    
    if [ -z "$address" ]; then
        print_error "Could not get Gateway address. The Gateway may not have an external IP yet."
        print_info "You can check the Gateway status with: kubectl get gateway ${gateway_name} -n ${namespace}"
        return 1
    fi
    
    print_header "Testing Advanced Routing Example"
    print_info "Gateway address: ${address}"
    
    echo -e "\n${CYAN}1. Testing Path-based Routing:${NC}"
    echo "Request to /v1:"
    response=$(curl -s -H "Host: example.com" "http://${address}/v1" 2>&1 || echo "Failed")
    echo "  Response: $response"
    
    echo -e "\nRequest to /v2:"
    response=$(curl -s -H "Host: example.com" "http://${address}/v2" 2>&1 || echo "Failed")
    echo "  Response: $response"
    
    echo -e "\n${CYAN}2. Testing Header-based Routing:${NC}"
    echo "Request with version: v1 header:"
    response=$(curl -s -H "Host: example.com" -H "version: v1" "http://${address}/" 2>&1 || echo "Failed")
    echo "  Response: $response"
    
    echo -e "\nRequest with version: v2 header:"
    response=$(curl -s -H "Host: example.com" -H "version: v2" "http://${address}/" 2>&1 || echo "Failed")
    echo "  Response: $response"
    
    echo -e "\n${CYAN}3. Testing Weighted Routing (canary.example.com):${NC}"
    echo "Making 10 requests to demonstrate traffic splitting:"
    local v1_count=0
    local v2_count=0
    for i in {1..10}; do
        response=$(curl -s -H "Host: canary.example.com" "http://${address}/" 2>&1 || echo "Failed")
        if echo "$response" | grep -q "Service V1"; then
            v1_count=$((v1_count + 1))
            echo -e "  Request $i: ${GREEN}V1${NC}"
        elif echo "$response" | grep -q "Service V2"; then
            v2_count=$((v2_count + 1))
            echo -e "  Request $i: ${BLUE}V2${NC}"
        else
            echo -e "  Request $i: ${YELLOW}$response${NC}"
        fi
        sleep 0.3
    done
    echo -e "\n${CYAN}Traffic Distribution:${NC} V1: ${v1_count}/10, V2: ${v2_count}/10 (Expected: ~80/20 split)"
}

test_rate_limiting() {
    local namespace=$1
    local gateway_name="rate-limiting-gateway"
    local address=$(get_gateway_address "${gateway_name}" "${namespace}")
    
    if [ -z "$address" ]; then
        print_error "Could not get Gateway address. The Gateway may not have an external IP yet."
        print_info "You can check the Gateway status with: kubectl get gateway ${gateway_name} -n ${namespace}"
        return 1
    fi
    
    print_header "Testing Rate Limiting Example"
    print_info "Gateway address: ${address}"
    print_info "Rate limit: 5 requests per minute"
    print_info "Making rapid requests to demonstrate rate limiting..."
    
    echo -e "\n${CYAN}Making 10 rapid requests:${NC}"
    local success_count=0
    local rate_limited_count=0
    local error_count=0
    
    for i in {1..10}; do
        response=$(curl -s -w "\nHTTP Status: %{http_code}" -H "Host: ratelimit.example.com" "http://${address}/" 2>&1)
        http_code=$(echo "$response" | grep "HTTP Status" | awk '{print $3}')
        body=$(echo "$response" | grep -v "HTTP Status")
        
        if [ "$http_code" = "200" ]; then
            success_count=$((success_count + 1))
            echo -e "  Request $i: ${GREEN}Success (200)${NC} - $body"
        elif [ "$http_code" = "429" ]; then
            rate_limited_count=$((rate_limited_count + 1))
            echo -e "  Request $i: ${RED}Rate Limited (429)${NC}"
        else
            error_count=$((error_count + 1))
            echo -e "  Request $i: ${YELLOW}HTTP $http_code${NC}"
        fi
        sleep 0.5
    done
    
    echo -e "\n${CYAN}Summary:${NC}"
    echo "  Successful requests (200): ${success_count}"
    echo "  Rate limited requests (429): ${rate_limited_count}"
    echo "  Other responses: ${error_count}"
    
    if [ $rate_limited_count -gt 0 ]; then
        print_success "Rate limiting is working! Some requests were rate limited."
    elif [ $success_count -eq 10 ]; then
        print_info "All requests succeeded. Rate limiting may not be configured or may need time to reset."
        print_info "Note: Rate limiting requires Envoy Gateway with RateLimitPolicy CRD installed."
    else
        print_info "Mixed results. Check Gateway controller logs for rate limiting configuration."
    fi
}

cleanup_example() {
    local namespace=$1
    
    print_header "Cleaning up ${namespace}"
    
    # Delete namespace (this will cascade delete all resources)
    if kubectl get namespace "${namespace}" &>/dev/null; then
        print_step "Deleting namespace ${namespace}..."
        kubectl delete namespace "${namespace}" --wait=true --timeout=60s || {
            print_error "Failed to delete namespace ${namespace}"
            print_info "You may need to delete it manually: kubectl delete namespace ${namespace}"
            return 1
        }
        print_success "Cleaned up ${namespace}"
    else
        print_info "Namespace ${namespace} does not exist, nothing to clean up"
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [EXAMPLE_NAME]

Deploy, test, and clean up Gateway API examples.

OPTIONS:
    -h, --help          Show this help message
    -l, --list          List available examples
    -d, --deploy-only   Only deploy, don't test
    -t, --test-only     Only test (assumes already deployed)
    -c, --cleanup-only  Only cleanup (specify namespace or example name)
    -k, --keep          Keep resources after testing (don't cleanup)
    -a, --all           Run all examples sequentially
    -n, --namespace     Specify namespace for test-only or cleanup-only

EXAMPLES:
    $0 basic-gateway              # Deploy, test, and cleanup basic-gateway
    $0 -d advanced-routing        # Only deploy advanced-routing
    $0 -t rate-limiting           # Only test rate-limiting (assumes deployed)
    $0 -c rate-limiting-test      # Cleanup namespace rate-limiting-test
    $0 -a                         # Run all examples
    $0 -l                         # List available examples

Available examples:
    - basic-gateway
    - advanced-routing
    - rate-limiting
EOF
}

list_examples() {
    print_header "Available Examples"
    for dir in ${EXAMPLES_DIR}/*/; do
        if [ -d "$dir" ]; then
            example_name=$(basename "$dir")
            echo "  - ${example_name}"
        fi
    done
}

main() {
    local deploy=true
    local test=true
    local cleanup=true
    local example_name=""
    local run_all=false
    local namespace=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -l|--list)
                list_examples
                exit 0
                ;;
            -d|--deploy-only)
                test=false
                cleanup=false
                shift
                ;;
            -t|--test-only)
                deploy=false
                cleanup=false
                shift
                ;;
            -c|--cleanup-only)
                deploy=false
                test=false
                shift
                ;;
            -k|--keep)
                cleanup=false
                shift
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            -n|--namespace)
                namespace="$2"
                shift 2
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                example_name="$1"
                shift
                ;;
        esac
    done
    
    # Check kubectl availability
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Handle cleanup-only mode
    if [ "$deploy" = false ] && [ "$test" = false ] && [ "$cleanup" = true ]; then
        if [ -z "$example_name" ] && [ -z "$namespace" ]; then
            print_error "Please specify an example name or namespace for cleanup"
            show_usage
            exit 1
        fi
        
        if [ -z "$namespace" ]; then
            # Try to find namespace from example
            namespace=$(kubectl get namespaces -o name | grep -i "${example_name}" | cut -d/ -f2 | head -1 || echo "")
            if [ -z "$namespace" ]; then
                print_error "Could not find namespace for example ${example_name}"
                exit 1
            fi
        fi
        
        cleanup_example "${namespace}"
        exit 0
    fi
    
    if [ "$run_all" = true ]; then
        # Run all examples
        for example_dir in ${EXAMPLES_DIR}/*/; do
            if [ -d "$example_dir" ]; then
                example=$(basename "$example_dir")
                # Skip non-example directories
                if [[ "$example" == "basic-gateway" || "$example" == "advanced-routing" || "$example" == "rate-limiting" ]]; then
                    print_header "Running example: ${example}"
                    
                    ns=""
                    if [ "$deploy" = true ]; then
                        ns=$(deploy_example "${example}")
                        sleep 5  # Give resources time to stabilize
                    else
                        # Try to find namespace
                        ns=$(kubectl get namespaces -o name | grep -i "${example}" | cut -d/ -f2 | head -1 || echo "")
                    fi
                    
                    if [ -z "$ns" ]; then
                        print_error "Could not determine namespace for ${example}"
                        continue
                    fi
                    
                    if [ "$test" = true ]; then
                        case "$example" in
                            basic-gateway)
                                test_basic_gateway "${ns}"
                                ;;
                            advanced-routing)
                                test_advanced_routing "${ns}"
                                ;;
                            rate-limiting)
                                test_rate_limiting "${ns}"
                                ;;
                            *)
                                print_info "No specific test function for ${example}, skipping test"
                                ;;
                        esac
                        sleep 2
                    fi
                    
                    if [ "$cleanup" = true ]; then
                        cleanup_example "${ns}"
                        sleep 2
                    fi
                fi
            fi
        done
    else
        # Run single example
        if [ -z "$example_name" ]; then
            print_error "Please specify an example name or use --all"
            show_usage
            exit 1
        fi
        
        ns=""
        if [ -n "$namespace" ]; then
            ns="$namespace"
        elif [ "$deploy" = true ]; then
            ns=$(deploy_example "${example_name}")
            sleep 5  # Give resources time to stabilize
        else
            # Try to find namespace
            ns=$(kubectl get namespaces -o name | grep -i "${example_name}" | cut -d/ -f2 | head -1 || echo "")
        fi
        
        if [ -z "$ns" ]; then
            print_error "Could not determine namespace for ${example_name}"
            exit 1
        fi
        
        if [ "$test" = true ]; then
            case "$example_name" in
                basic-gateway)
                    test_basic_gateway "${ns}"
                    ;;
                advanced-routing)
                    test_advanced_routing "${ns}"
                    ;;
                rate-limiting)
                    test_rate_limiting "${ns}"
                    ;;
                *)
                    print_info "No specific test function for ${example_name}, skipping test"
                    ;;
            esac
        fi
        
        if [ "$cleanup" = true ]; then
            cleanup_example "${ns}"
        fi
    fi
    
    print_success "Demo completed!"
}

main "$@"

