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
KUBECONFIG_FILE="${SCRIPT_DIR}/kubeconfig.yaml"
DEMO_DIR="${SCRIPT_DIR}/demo"
NAMESPACE="gateway-demos"
SHARED_GATEWAY_NAME="shared-gateway"
SHARED_GATEWAY_ADDRESS=""  # Cached gateway address

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

get_gateway_address() {
    local gateway_name=$1
    local namespace=$2
    
    print_info "Getting Gateway address for ${gateway_name}..." >&2
    
    local address=""
    local max_attempts=30
    local attempt=0
    
    while [ -z "$address" ] && [ $attempt -lt $max_attempts ]; do
        address=$(kubectl get gateway ${gateway_name} -n ${namespace} -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
        
        if [ -z "$address" ]; then
            sleep 2
            attempt=$((attempt + 1))
        fi
    done
    
    if [ -z "$address" ]; then
        print_error "Could not get Gateway address for ${gateway_name}" >&2
        return 1
    fi
    
    echo "$address"
}

wait_for_gateway() {
    local gateway_name=$1
    local namespace=$2
    
    print_info "Waiting for Gateway ${gateway_name} to be ready..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local status=$(kubectl get gateway ${gateway_name} -n ${namespace} -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
        if [ "$status" = "True" ]; then
            print_success "Gateway ${gateway_name} is ready"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "Gateway ${gateway_name} did not become ready in time"
    return 1
}

ensure_shared_gateway() {
    # Check if shared gateway already exists
    if kubectl get gateway ${SHARED_GATEWAY_NAME} -n ${NAMESPACE} &>/dev/null; then
        print_info "Shared gateway already exists, reusing it..."
    else
        print_step "Deploying shared gateway..."
        kubectl apply -f "${DEMO_DIR}/gateway.yaml"
        wait_for_gateway "${SHARED_GATEWAY_NAME}" "${NAMESPACE}"
    fi
    
    # Cache the gateway address
    if [ -z "$SHARED_GATEWAY_ADDRESS" ]; then
        SHARED_GATEWAY_ADDRESS=$(get_gateway_address "${SHARED_GATEWAY_NAME}" "${NAMESPACE}") || {
            print_error "Failed to get shared Gateway address"
            return 1
        }
        print_success "Shared gateway address: ${SHARED_GATEWAY_ADDRESS}"
    fi
}

demo_basic_routing() {
    print_header "Demo: Basic Routing"
    
    ensure_shared_gateway || return 1
    
    print_step "Deploying basic routing HTTPRoute..."
    kubectl apply -f "${DEMO_DIR}/basic-routing/httproute.yaml"
    
    # Give HTTPRoute a moment to be processed
    sleep 2
    
    local address="$SHARED_GATEWAY_ADDRESS"
    
    print_step "Testing basic routing..."
    echo -e "\n${CYAN}Making requests to http://${address}/${NC}"
    for i in {1..5}; do
        response=$(curl -s -w "\nHTTP Status: %{http_code}" -H "Host: example.com" "http://${address}/" 2>&1)
        http_code=$(echo "$response" | grep "HTTP Status" | awk '{print $3}')
        body=$(echo "$response" | grep -v "HTTP Status")
        if [ "$http_code" = "200" ]; then
            echo -e "Request $i: ${GREEN}Success (200)${NC} - $body"
        elif [ "$http_code" = "500" ]; then
            echo -e "Request $i: ${RED}Server Error (500)${NC}"
            echo -e "  ${RED}Error message:${NC} $body"
        else
            echo -e "Request $i: ${YELLOW}HTTP $http_code${NC} - $body"
        fi
        sleep 0.5
    done
    
    print_success "Basic routing demo complete"
}

demo_advanced_routing() {
    print_header "Demo: Advanced Routing (Weighted Load Balancing)"
    
    ensure_shared_gateway || return 1
    
    print_step "Deploying advanced routing HTTPRoute..."
    kubectl apply -f "${DEMO_DIR}/advanced-routing/httproute.yaml"
    
    # Give HTTPRoute a moment to be processed
    sleep 2
    
    local address="$SHARED_GATEWAY_ADDRESS"
    
    print_step "Testing weighted load balancing (80/20 split)..."
    echo -e "\n${CYAN}Making 20 requests to http://${address}/ (Host: weighted.example.com)${NC}"
    local v1_count=0
    local v2_count=0
    local error_count=0
    
    for i in {1..20}; do
        response=$(curl -s -w "\nHTTP Status: %{http_code}" -H "Host: weighted.example.com" "http://${address}/" 2>&1)
        http_code=$(echo "$response" | grep "HTTP Status" | awk '{print $3}')
        body=$(echo "$response" | grep -v "HTTP Status")
        
        if [ "$http_code" = "200" ]; then
            if echo "$body" | grep -q "V1"; then
                v1_count=$((v1_count + 1))
                echo -e "Request $i: ${GREEN}V1${NC} - $body"
            elif echo "$body" | grep -q "V2"; then
                v2_count=$((v2_count + 1))
                echo -e "Request $i: ${BLUE}V2${NC} - $body"
            else
                echo -e "Request $i: ${YELLOW}$body${NC}"
            fi
        elif [ "$http_code" = "500" ]; then
            error_count=$((error_count + 1))
            echo -e "Request $i: ${RED}Server Error (500)${NC}"
            echo -e "  ${RED}Error message:${NC} $body"
        else
            echo -e "Request $i: ${YELLOW}HTTP $http_code${NC} - $body"
        fi
        sleep 0.3
    done
    
    if [ $error_count -gt 0 ]; then
        echo -e "\n${RED}Warning: $error_count requests returned 500 errors${NC}"
    fi
    
    echo -e "\n${CYAN}Traffic Distribution Summary:${NC}"
    local total_success=$((v1_count + v2_count))
    if [ $total_success -gt 0 ]; then
        echo "  V1 (80% weight): ${v1_count}/$total_success requests (${GREEN}$((v1_count * 100 / total_success))%${NC})"
        echo "  V2 (20% weight): ${v2_count}/$total_success requests (${BLUE}$((v2_count * 100 / total_success))%${NC})"
    fi
    if [ $error_count -gt 0 ]; then
        echo "  ${RED}Errors: $error_count/20 requests (500)${NC}"
    fi
    
    print_success "Advanced routing demo complete"
}

demo_basic_auth() {
    print_header "Demo: Basic Authentication"
    
    ensure_shared_gateway || return 1
    
    print_step "Deploying basic auth HTTPRoute and SecurityPolicy..."
    kubectl apply -f "${DEMO_DIR}/basic-auth/httproute.yaml"
    
    # Wait a bit for SecurityPolicy to be applied
    sleep 5
    
    local address="$SHARED_GATEWAY_ADDRESS"
    
    print_step "Testing basic authentication..."
    echo -e "\n${CYAN}Test 1: Request without authentication (should fail)${NC}"
    response=$(curl -s -w "\nHTTP Status: %{http_code}" -H "Host: auth.example.com" "http://${address}/" 2>&1)
    http_code=$(echo "$response" | grep "HTTP Status" | awk '{print $3}')
    body=$(echo "$response" | grep -v "HTTP Status")
    if [ "$http_code" = "401" ]; then
        echo -e "${GREEN}✓ Correctly rejected (401 Unauthorized)${NC}"
    elif [ "$http_code" = "500" ]; then
        echo -e "${RED}✗ Server Error (500)${NC}"
        echo -e "  ${RED}Error message:${NC} $body"
    else
        echo -e "${YELLOW}Response: HTTP $http_code${NC} - $body"
    fi
    
    echo -e "\n${CYAN}Test 2: Request with valid credentials (admin/admin123)${NC}"
    response=$(curl -s -w "\nHTTP Status: %{http_code}" -u admin:admin123 -H "Host: auth.example.com" "http://${address}/" 2>&1)
    http_code=$(echo "$response" | grep "HTTP Status" | awk '{print $3}')
    body=$(echo "$response" | grep -v "HTTP Status")
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✓ Authentication successful (200 OK)${NC}"
        echo "Response: $body"
    elif [ "$http_code" = "500" ]; then
        echo -e "${RED}✗ Server Error (500)${NC}"
        echo -e "  ${RED}Error message:${NC} $body"
    else
        echo -e "${YELLOW}Response: HTTP $http_code${NC} - $body"
    fi
    
    echo -e "\n${CYAN}Test 3: Request with invalid credentials${NC}"
    response=$(curl -s -w "\nHTTP Status: %{http_code}" -u wrong:password -H "Host: auth.example.com" "http://${address}/" 2>&1)
    http_code=$(echo "$response" | grep "HTTP Status" | awk '{print $3}')
    body=$(echo "$response" | grep -v "HTTP Status")
    if [ "$http_code" = "401" ]; then
        echo -e "${GREEN}✓ Correctly rejected (401 Unauthorized)${NC}"
    elif [ "$http_code" = "500" ]; then
        echo -e "${RED}✗ Server Error (500)${NC}"
        echo -e "  ${RED}Error message:${NC} $body"
    else
        echo -e "${YELLOW}Response: HTTP $http_code${NC} - $body"
    fi
    
    print_success "Basic auth demo complete"
}

demo_rate_limiting() {
    print_header "Demo: Rate Limiting"
    
    ensure_shared_gateway || return 1
    
    print_step "Deploying rate limiting HTTPRoute and BackendTrafficPolicy..."
    kubectl apply -f "${DEMO_DIR}/rate-limiting/httproute.yaml"
    
    # Wait a bit for BackendTrafficPolicy to be applied
    sleep 5
    
    local address="$SHARED_GATEWAY_ADDRESS"
    
    print_step "Testing rate limiting (5 requests per minute)..."
    echo -e "\n${CYAN}Making 10 rapid requests to http://${address}/ (Host: ratelimit.example.com)${NC}"
    local success_count=0
    local rate_limited_count=0
    
    for i in {1..10}; do
        response=$(curl -s -w "\nHTTP Status: %{http_code}" -H "Host: ratelimit.example.com" "http://${address}/" 2>&1)
        http_code=$(echo "$response" | grep "HTTP Status" | awk '{print $3}')
        body=$(echo "$response" | grep -v "HTTP Status")
        
        if [ "$http_code" = "200" ]; then
            success_count=$((success_count + 1))
            echo -e "Request $i: ${GREEN}Success (200)${NC} - $body"
        elif [ "$http_code" = "429" ]; then
            rate_limited_count=$((rate_limited_count + 1))
            echo -e "Request $i: ${RED}Rate Limited (429)${NC}"
        elif [ "$http_code" = "500" ]; then
            echo -e "Request $i: ${RED}Server Error (500)${NC}"
            echo -e "  ${RED}Error message:${NC} $body"
        else
            echo -e "Request $i: ${YELLOW}HTTP $http_code${NC} - $body"
        fi
        sleep 0.5
    done
    
    echo -e "\n${CYAN}Rate Limiting Summary:${NC}"
    echo "  Successful requests (200): ${success_count}"
    echo "  Rate limited requests (429): ${rate_limited_count}"
    
    if [ $rate_limited_count -gt 0 ]; then
        print_success "Rate limiting is working!"
    else
        print_info "Rate limiting may need more time to apply or reset"
    fi
    
    print_success "Rate limiting demo complete"
}

demo_tls() {
    print_header "Demo: TLS/HTTPS Termination"
    
    # First, deploy the ClusterIssuer (needs to exist before Certificate)
    print_info "Creating ClusterIssuer..."
    kubectl apply -f "${DEMO_DIR}/tls/issuer.yaml"
    
    # Wait a moment for ClusterIssuer to be ready
    sleep 2
    
    # Deploy Certificate (needed for HTTPS listener)
    print_info "Creating Certificate..."
    kubectl apply -f "${DEMO_DIR}/tls/certificate.yaml"
    
    # Wait for certificate to be issued
    print_info "Waiting for certificate to be issued by cert-manager..."
    local max_attempts=60
    local attempt=0
    local cert_ready=""
    while [ $attempt -lt $max_attempts ]; do
        cert_ready=$(kubectl get certificate tls-cert -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        if [ "$cert_ready" = "True" ]; then
            print_success "Certificate is ready"
            break
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [ "$cert_ready" != "True" ]; then
        print_error "Certificate did not become ready in time"
        print_info "Check certificate status with: kubectl describe certificate tls-cert -n ${NAMESPACE}"
    fi
    
    # Ensure shared gateway is deployed (it will pick up the certificate)
    ensure_shared_gateway || return 1
    
    # Wait a moment for gateway to pick up the certificate
    sleep 3
    
    print_step "Deploying TLS HTTPRoute..."
    kubectl apply -f "${DEMO_DIR}/tls/httproute.yaml"
    
    # Give HTTPRoute a moment to be processed
    sleep 2
    
    local address="$SHARED_GATEWAY_ADDRESS"
    
    print_step "Testing TLS/HTTPS termination..."
    echo -e "\n${CYAN}Test 1: HTTPS request (self-signed cert, using -k to skip verification)${NC}"
    response=$(curl -k -s -w "\nHTTP Status: %{http_code}" -H "Host: tls.example.com" "https://${address}/" 2>&1)
    http_code=$(echo "$response" | grep "HTTP Status" | awk '{print $3}')
    body=$(echo "$response" | grep -v "HTTP Status")
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✓ HTTPS request successful (200 OK)${NC}"
        echo "Response: $body"
    elif [ "$http_code" = "500" ]; then
        echo -e "${RED}✗ Server Error (500)${NC}"
        echo -e "  ${RED}Error message:${NC} $body"
    else
        echo -e "${YELLOW}Response: HTTP $http_code${NC} - $body"
    fi
    
    echo -e "\n${CYAN}Test 2: HTTP request (should still work)${NC}"
    response=$(curl -s -w "\nHTTP Status: %{http_code}" -H "Host: tls.example.com" "http://${address}/" 2>&1)
    http_code=$(echo "$response" | grep "HTTP Status" | awk '{print $3}')
    body=$(echo "$response" | grep -v "HTTP Status")
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✓ HTTP request successful (200 OK)${NC}"
        echo "Response: $body"
    else
        echo -e "${YELLOW}Response: HTTP $http_code${NC} - $body"
    fi
    
    echo -e "\n${CYAN}Certificate Information:${NC}"
    kubectl get certificate tls-cert -n ${NAMESPACE} -o jsonpath='{.status}' 2>/dev/null | grep -q "notAfter" && {
        echo "  Certificate status: $(kubectl get certificate tls-cert -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
        echo "  Issuer: $(kubectl get certificate tls-cert -n ${NAMESPACE} -o jsonpath='{.spec.issuerRef.name}')"
    } || echo "  Certificate details available via: kubectl describe certificate tls-cert -n ${NAMESPACE}"
    
    print_success "TLS demo complete"
    print_info "Note: Self-signed certificates will show browser warnings. For production, use Let's Encrypt."
}

cleanup_demo() {
    local demo_name=$1
    
    print_header "Cleaning up: ${demo_name}"
    
    case "$demo_name" in
        basic-routing)
            print_step "Removing basic routing HTTPRoute..."
            kubectl delete -f "${DEMO_DIR}/basic-routing/httproute.yaml" --ignore-not-found=true
            ;;
        advanced-routing)
            print_step "Removing advanced routing HTTPRoute..."
            kubectl delete -f "${DEMO_DIR}/advanced-routing/httproute.yaml" --ignore-not-found=true
            ;;
        basic-auth)
            print_step "Removing basic auth HTTPRoute and SecurityPolicy..."
            kubectl delete -f "${DEMO_DIR}/basic-auth/httproute.yaml" --ignore-not-found=true
            ;;
        rate-limiting)
            print_step "Removing rate limiting HTTPRoute and BackendTrafficPolicy..."
            kubectl delete -f "${DEMO_DIR}/rate-limiting/httproute.yaml" --ignore-not-found=true
            ;;
        tls)
            print_step "Removing TLS HTTPRoute, Certificate, and ClusterIssuer..."
            kubectl delete -f "${DEMO_DIR}/tls/httproute.yaml" --ignore-not-found=true
            kubectl delete -f "${DEMO_DIR}/tls/certificate.yaml" --ignore-not-found=true
            kubectl delete clusterissuer selfsigned-issuer --ignore-not-found=true
            ;;
        all)
            print_step "Removing all demo HTTPRoutes and policies..."
            kubectl delete -f "${DEMO_DIR}/basic-routing/httproute.yaml" --ignore-not-found=true
            kubectl delete -f "${DEMO_DIR}/advanced-routing/httproute.yaml" --ignore-not-found=true
            kubectl delete -f "${DEMO_DIR}/basic-auth/httproute.yaml" --ignore-not-found=true
            kubectl delete -f "${DEMO_DIR}/rate-limiting/httproute.yaml" --ignore-not-found=true
            kubectl delete -f "${DEMO_DIR}/tls/httproute.yaml" --ignore-not-found=true
            kubectl delete -f "${DEMO_DIR}/tls/certificate.yaml" --ignore-not-found=true
            kubectl delete clusterissuer selfsigned-issuer --ignore-not-found=true
            print_step "Removing shared gateway..."
            kubectl delete -f "${DEMO_DIR}/gateway.yaml" --ignore-not-found=true
            ;;
        services)
            print_step "Removing demo services and shared gateway..."
            kubectl delete -f "${DEMO_DIR}/services.yaml" --ignore-not-found=true
            kubectl delete -f "${DEMO_DIR}/gateway.yaml" --ignore-not-found=true
            ;;
        *)
            print_error "Unknown demo: $demo_name"
            return 1
            ;;
    esac
    
    print_success "Cleanup complete for ${demo_name}"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [DEMO_NAME]

Run Gateway API demos to showcase different routing capabilities.

OPTIONS:
    -h, --help          Show this help message
    -c, --cleanup       Cleanup demo resources instead of running demo
    -l, --list          List available demos

DEMO_NAME:
    basic-routing      - Basic HTTP routing to a single backend
    advanced-routing   - Weighted load balancing (80/20 split)
    basic-auth         - Basic authentication protection
    rate-limiting      - Rate limiting (5 requests/minute)
    tls                - TLS/HTTPS termination with cert-manager
    all                - Run/cleanup all demos
    services           - Cleanup demo services (only with --cleanup)

Examples:
    $0 basic-routing              # Run basic routing demo
    $0 --cleanup basic-routing    # Cleanup basic routing resources
    $0 --cleanup all              # Cleanup all demo resources
    $0 --cleanup services         # Cleanup demo services
    $0 all                        # Run all demos

Prerequisites:
    - Cluster must be set up (run ./setup.sh first)
    - KUBECONFIG must be set or kubeconfig.yaml must exist
EOF
}

main() {
    local cleanup_mode=false
    local list_mode=false
    local demo_name=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--cleanup)
                cleanup_mode=true
                shift
                ;;
            -l|--list)
                list_mode=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                demo_name="$1"
                shift
                ;;
        esac
    done
    
    # Check prerequisites
    if [ ! -f "${KUBECONFIG_FILE}" ]; then
        print_error "Kubeconfig not found: ${KUBECONFIG_FILE}"
        print_info "Please run ./setup.sh first to provision the cluster"
        exit 1
    fi
    
    export KUBECONFIG="${KUBECONFIG_FILE}"
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Handle list mode
    if [ "$list_mode" = true ]; then
        print_header "Available Demos"
        echo "  - basic-routing      - Basic HTTP routing to a single backend"
        echo "  - advanced-routing   - Weighted load balancing (80/20 split)"
        echo "  - basic-auth         - Basic authentication protection"
        echo "  - rate-limiting      - Rate limiting (5 requests/minute)"
        echo "  - tls                - TLS/HTTPS termination with cert-manager"
        echo "  - all                - Run/cleanup all demos"
        exit 0
    fi
    
    # Handle cleanup mode
    if [ "$cleanup_mode" = true ]; then
        if [ -z "$demo_name" ]; then
            print_error "Please specify a demo name to cleanup"
            show_usage
            exit 1
        fi
        
        cleanup_demo "$demo_name"
        exit 0
    fi
    
    # Check if demo services are installed (only for running demos, not cleanup)
    if ! kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        print_error "Demo namespace '${NAMESPACE}' not found"
        print_info "Please run ./setup.sh first to install demo services"
        exit 1
    fi
    
    if [ -z "$demo_name" ]; then
        show_usage
        exit 1
    fi
    
    # Run demos
    case "$demo_name" in
        basic-routing)
            demo_basic_routing
            ;;
        advanced-routing)
            demo_advanced_routing
            ;;
        basic-auth)
            demo_basic_auth
            ;;
        rate-limiting)
            demo_rate_limiting
            ;;
        tls)
            demo_tls
            ;;
        all)
            # Ensure shared gateway is set up once before running all demos
            ensure_shared_gateway || {
                print_error "Failed to set up shared gateway"
                exit 1
            }
            echo ""
            demo_basic_routing
            echo ""
            demo_advanced_routing
            echo ""
            demo_basic_auth
            echo ""
            demo_rate_limiting
            echo ""
            demo_tls
            ;;
        *)
            print_error "Unknown demo: $demo_name"
            show_usage
            exit 1
            ;;
    esac
    
    print_success "Demo completed!"
}

main "$@"

