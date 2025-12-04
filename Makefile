.PHONY: help stage1-cluster stage2-gateway stage3-demos clean-stage1 clean-stage2 clean-stage3 clean-all
.PHONY: demo-basic demo-advanced demo-rate-limit demo-all
.PHONY: check-prerequisites

# Configuration
KUBECONFIG ?= $(shell pwd)/kubeconfig.yaml
TERRAFORM_DIR = terraform
EXAMPLES_DIR = examples
SCRIPTS_DIR = scripts

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

help: ## Show this help message
	@echo "$(BLUE)Gateway API Examples - Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Stages:$(NC)"
	@echo "  make stage1-cluster     - Provision Kubernetes cluster and node pools"
	@echo "  make stage2-gateway     - Install Envoy Gateway and GatewayClass"
	@echo "  make stage3-demos       - Install all demo examples"
	@echo ""
	@echo "$(GREEN)Demos:$(NC)"
	@echo "  make demo-basic         - Run basic gateway demo"
	@echo "  make demo-advanced      - Run advanced routing demo"
	@echo "  make demo-rate-limit     - Run rate limiting demo"
	@echo "  make demo-all           - Run all demos"
	@echo ""
	@echo "$(GREEN)Cleanup:$(NC)"
	@echo "  make clean-stage1       - Destroy cluster (Stage 1)"
	@echo "  make clean-stage2       - Remove Gateway resources (Stage 2)"
	@echo "  make clean-stage3       - Remove demo examples (Stage 3)"
	@echo "  make clean-all          - Clean everything"
	@echo ""
	@echo "$(GREEN)Utilities:$(NC)"
	@echo "  make check-prerequisites - Check if required tools are installed"

check-prerequisites: ## Check if required tools are installed
	@echo "$(BLUE)Checking prerequisites...$(NC)"
	@command -v terraform >/dev/null 2>&1 || { echo "$(RED)✗ terraform is not installed$(NC)"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)✗ kubectl is not installed$(NC)"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "$(RED)✗ helm is not installed$(NC)"; exit 1; }
	@command -v curl >/dev/null 2>&1 || { echo "$(RED)✗ curl is not installed$(NC)"; exit 1; }
	@echo "$(GREEN)✓ All prerequisites are installed$(NC)"

# Stage 1: Cluster Provisioning
stage1-cluster: check-prerequisites ## Provision Kubernetes cluster and node pools
	@echo "$(BLUE)========================================$(NC)"
	@echo "$(BLUE)Stage 1: Provisioning Cluster$(NC)"
	@echo "$(BLUE)========================================$(NC)"
	@cd $(TERRAFORM_DIR) && terraform init
	@cd $(TERRAFORM_DIR) && terraform apply -auto-approve
	@echo "$(GREEN)✓ Stage 1 complete: Cluster provisioned$(NC)"
	@echo "$(YELLOW)Kubeconfig saved to: $(KUBECONFIG)$(NC)"

clean-stage1: ## Destroy cluster (Stage 1)
	@echo "$(BLUE)Destroying cluster...$(NC)"
	@cd $(TERRAFORM_DIR) && terraform destroy -auto-approve || true
	@echo "$(GREEN)✓ Stage 1 cleanup complete$(NC)"

# Stage 2: Gateway Installation
stage2-gateway: check-prerequisites ## Install Gateway API CRDs, Envoy Gateway and GatewayClass
	@echo "$(BLUE)========================================$(NC)"
	@echo "$(BLUE)Stage 2: Installing Envoy Gateway$(NC)"
	@echo "$(BLUE)========================================$(NC)"
	@test -f $(KUBECONFIG) || { echo "$(RED)✗ Kubeconfig not found. Run 'make stage1-cluster' first$(NC)"; exit 1; }
	@export KUBECONFIG=$(KUBECONFIG) && \
		echo "$(YELLOW)Installing Gateway API CRDs...$(NC)" && \
		kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
	@export KUBECONFIG=$(KUBECONFIG) && \
		echo "$(YELLOW)Waiting for Gateway API CRDs to be ready...$(NC)" && \
		kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=60s && \
		kubectl wait --for=condition=Established crd/httproutes.gateway.networking.k8s.io --timeout=60s
	@export KUBECONFIG=$(KUBECONFIG) && \
		echo "$(YELLOW)Installing Cert-Manager...$(NC)" && \
		helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
			--namespace cert-manager --create-namespace \
			--version v1.19.0 \
			--set crds.enabled=true \
			--wait --timeout 5m || true
	@export KUBECONFIG=$(KUBECONFIG) && \
		echo "$(YELLOW)Installing Envoy Gateway...$(NC)" && \
		helm upgrade --install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
			--namespace envoy-gateway-system --create-namespace \
			--version v1.6.0 \
			--wait --timeout 5m
	@export KUBECONFIG=$(KUBECONFIG) && \
		echo "$(YELLOW)Installing EnvoyProxy configuration...$(NC)" && \
		kubectl apply -f $(EXAMPLES_DIR)/envoy-proxy-config.yaml
	@export KUBECONFIG=$(KUBECONFIG) && \
		echo "$(YELLOW)Installing GatewayClass...$(NC)" && \
		kubectl apply -f $(EXAMPLES_DIR)/gateway-class.yaml
	@export KUBECONFIG=$(KUBECONFIG) && \
		echo "$(YELLOW)Waiting for GatewayClass to be ready...$(NC)" && \
		kubectl wait --for=condition=Accepted gatewayclass/envoy-gateway-class --timeout=300s || true
	@echo "$(GREEN)✓ Stage 2 complete: Envoy Gateway installed$(NC)"

clean-stage2: ## Remove Gateway resources (Stage 2)
	@echo "$(BLUE)Removing Gateway resources...$(NC)"
	@export KUBECONFIG=$(KUBECONFIG) && \
		kubectl delete gatewayclass envoy-gateway-class --ignore-not-found=true && \
		kubectl delete envoyproxy envoy-proxy-config -n envoy-gateway-system --ignore-not-found=true && \
		helm uninstall envoy-gateway -n envoy-gateway-system --ignore-not-found=true && \
		helm uninstall cert-manager -n cert-manager --ignore-not-found=true
	@echo "$(GREEN)✓ Stage 2 cleanup complete$(NC)"

# Stage 3: Demo Examples
stage3-demos: stage2-gateway stage3-basic stage3-advanced stage3-rate-limit ## Install all demo examples
	@echo "$(GREEN)✓ All demo examples installed$(NC)"

stage3-basic: check-prerequisites ## Install basic gateway example
	@echo "$(BLUE)Installing basic gateway example...$(NC)"
	@test -f $(KUBECONFIG) || { echo "$(RED)✗ Kubeconfig not found. Run 'make stage1-cluster' first$(NC)"; exit 1; }
	@export KUBECONFIG=$(KUBECONFIG) && \
		echo "$(YELLOW)Applying namespace and gateway...$(NC)" && \
		kubectl apply -f $(EXAMPLES_DIR)/basic-gateway/namespace.yaml && \
		kubectl apply -f $(EXAMPLES_DIR)/basic-gateway/gateway.yaml && \
		echo "$(YELLOW)Applying application resources...$(NC)" && \
		kubectl apply -f $(EXAMPLES_DIR)/basic-gateway/app.yaml && \
		kubectl apply -f $(EXAMPLES_DIR)/basic-gateway/httproute.yaml && \
		kubectl wait --for=condition=ready pod -l app=example-app -n gateway-api-test --timeout=300s || true
	@echo "$(GREEN)✓ Basic gateway example installed$(NC)"

stage3-advanced: check-prerequisites ## Install advanced routing example
	@echo "$(BLUE)Installing advanced routing example...$(NC)"
	@test -f $(KUBECONFIG) || { echo "$(RED)✗ Kubeconfig not found. Run 'make stage1-cluster' first$(NC)"; exit 1; }
	@export KUBECONFIG=$(KUBECONFIG) && \
		echo "$(YELLOW)Applying namespace and gateway...$(NC)" && \
		kubectl apply -f $(EXAMPLES_DIR)/advanced-routing/namespace-gateway.yaml && \
		echo "$(YELLOW)Applying backend services...$(NC)" && \
		kubectl apply -f $(EXAMPLES_DIR)/advanced-routing/backend-services.yaml && \
		echo "$(YELLOW)Applying HTTPRoutes...$(NC)" && \
		kubectl apply -f $(EXAMPLES_DIR)/advanced-routing/httproutes.yaml && \
		kubectl wait --for=condition=ready pod -l app=service-v1 -n advanced-routing-test --timeout=300s || true && \
		kubectl wait --for=condition=ready pod -l app=service-v2 -n advanced-routing-test --timeout=300s || true
	@echo "$(GREEN)✓ Advanced routing example installed$(NC)"

stage3-rate-limit: check-prerequisites ## Install rate limiting example
	@echo "$(BLUE)Installing rate limiting example...$(NC)"
	@test -f $(KUBECONFIG) || { echo "$(RED)✗ Kubeconfig not found. Run 'make stage1-cluster' first$(NC)"; exit 1; }
	@export KUBECONFIG=$(KUBECONFIG) && \
		echo "$(YELLOW)Applying namespace and gateway...$(NC)" && \
		kubectl apply -f $(EXAMPLES_DIR)/rate-limiting/namespace-gateway.yaml && \
		echo "$(YELLOW)Applying backend service...$(NC)" && \
		kubectl apply -f $(EXAMPLES_DIR)/rate-limiting/backend-service.yaml && \
		echo "$(YELLOW)Applying HTTPRoute and RateLimitPolicy...$(NC)" && \
		kubectl apply -f $(EXAMPLES_DIR)/rate-limiting/httproutes.yaml && \
		kubectl wait --for=condition=ready pod -l app=rate-limited-app -n rate-limiting-test --timeout=300s || true
	@echo "$(GREEN)✓ Rate limiting example installed$(NC)"

clean-stage3: ## Remove demo examples (Stage 3)
	@echo "$(BLUE)Removing demo examples...$(NC)"
	@export KUBECONFIG=$(KUBECONFIG) && \
		kubectl delete -f $(EXAMPLES_DIR)/basic-gateway/ --ignore-not-found=true && \
		kubectl delete -f $(EXAMPLES_DIR)/advanced-routing/ --ignore-not-found=true && \
		kubectl delete -f $(EXAMPLES_DIR)/rate-limiting/ --ignore-not-found=true
	@echo "$(GREEN)✓ Stage 3 cleanup complete$(NC)"

# Demo Scripts
demo-basic: stage2-gateway stage3-basic ## Run basic gateway demo
	@test -f $(KUBECONFIG) || { echo "$(RED)✗ Kubeconfig not found. Run 'make stage1-cluster' first$(NC)"; exit 1; }
	@export KUBECONFIG=$(KUBECONFIG) && $(SCRIPTS_DIR)/demo.sh --test-only --namespace gateway-api-test basic-gateway

demo-advanced: stage2-gateway stage3-advanced ## Run advanced routing demo
	@test -f $(KUBECONFIG) || { echo "$(RED)✗ Kubeconfig not found. Run 'make stage1-cluster' first$(NC)"; exit 1; }
	@export KUBECONFIG=$(KUBECONFIG) && $(SCRIPTS_DIR)/demo.sh --test-only --namespace advanced-routing-test advanced-routing

demo-rate-limit: stage2-gateway stage3-rate-limit ## Run rate limiting demo
	@test -f $(KUBECONFIG) || { echo "$(RED)✗ Kubeconfig not found. Run 'make stage1-cluster' first$(NC)"; exit 1; }
	@export KUBECONFIG=$(KUBECONFIG) && $(SCRIPTS_DIR)/demo.sh --test-only --namespace rate-limiting-test rate-limiting

demo-all: stage2-gateway stage3-demos ## Run all demos
	@test -f $(KUBECONFIG) || { echo "$(RED)✗ Kubeconfig not found. Run 'make stage1-cluster' first$(NC)"; exit 1; }
	@export KUBECONFIG=$(KUBECONFIG) && $(SCRIPTS_DIR)/demo.sh --test-only --all

clean-all: clean-stage3 clean-stage2 clean-stage1 ## Clean everything
	@echo "$(GREEN)✓ All resources cleaned$(NC)"

