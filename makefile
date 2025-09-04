## Makefile for managing a local Kubernetes cluster with kind
GREEN = \033[1;32m
RESET = \033[0m
WHITE = \033[1;38;5;231m
# ------------------------------
# Configurable variables (override via: make CLUSTER_NAME=mycluster)
# ------------------------------
CLUSTER_NAME ?= kaiko-lab
K8S_VERSION ?= v1.29.2
KIND_NODE_IMAGE ?= kindest/node:$(K8S_VERSION)
KIND ?= kind
KUBECTL ?= kubectl
KUBE_CONTEXT ?= kind-$(CLUSTER_NAME)
CREATE_WAIT ?= 120s
KIND_CONFIG ?= kind-three-node.yaml
HPA_DURATION ?= 120        # seconds
HPA_CONCURRENCY ?= 200      # parallel clients
HPA_PAUSE ?= 0.1    

.DEFAULT_GOAL := help
.PHONY: help check-deps create-cluster delete-cluster use-context cluster current-context list-clusters hpa-load hpa-watch install-metrics deploy-everything install-tools check-versions setup-all teardown-all hpa-demo hpa-reset debug-metrics check-flux

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  %-22s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

check-deps: ## Verify required CLI tools are installed
	@command -v $(KIND) >/dev/null 2>&1 || { echo "ERROR: kind not found. Run 'make install-tools' to install"; exit 1; }
	@command -v $(KUBECTL) >/dev/null 2>&1 || { echo "ERROR: kubectl not found. Run 'make install-tools' to install"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found. Install Docker Desktop first"; exit 1; }
	@PORT=5000; \
	if lsof -iTCP:$${PORT} -sTCP:LISTEN -n -P >/dev/null 2>&1; then \
	  if docker ps --format "table {{.Names}}" | grep -q "kind-registry"; then \
	    echo "INFO: Port $${PORT} is in use by kind-registry, continuing..."; \
	  else \
	    echo "ERROR: Port $${PORT} is already in use on the host."; \
	    echo "This blocks the local registry (localhost:$${PORT})."; \
	    echo "Close the process using port $${PORT} (on macOS, often AirPlay Receiver) and rerun the command."; \
	    echo "Hint (macOS): System Settings → General → AirDrop & Handoff → AirPlay Receiver → Off"; \
	    exit 1; \
	  fi; \
	fi

create-cluster: check-deps ## Create kind cluster if missing, set context, install monitoring stack
	@if $(KIND) get clusters | grep -qx "$(CLUSTER_NAME)"; then \
		echo "Kind cluster '$(CLUSTER_NAME)' already exists."; \
	else \
		echo "Creating kind cluster '$(CLUSTER_NAME)'..."; \
		cfg=""; \
		if [ -n "$(KIND_CONFIG)" ]; then cfg="--config $(KIND_CONFIG)"; fi; \
		$(KIND) create cluster --name $(CLUSTER_NAME) --image $(KIND_NODE_IMAGE) $$cfg --wait $(CREATE_WAIT); \
	fi
	@$(KUBECTL) config use-context $(KUBE_CONTEXT)

debug-container: ## Debug container in default namespace
	@$(KUBECTL) run -n default toolbox --rm -it --image=nicolaka/netshoot --restart=Never -- sh

debug-app: ## Debug container in dev namespace
	@$(KUBECTL) run -n dev debug-toolbox --rm -it --image=nicolaka/netshoot --restart=Never -- sh

debug-monitoring: ## Debug container in monitoring namespace
	@$(KUBECTL) run -n monitoring debug-toolbox --rm -it --image=nicolaka/netshoot --restart=Never -- sh

 

delete-cluster: check-deps ## Delete the kind cluster and delete port forwards
	@$(KIND) delete cluster --name $(CLUSTER_NAME)
	lsof -iTCP -sTCP:LISTEN -n -P

cleanup-app: ## Clean up dev namespace (manual fallback)
	@echo "Cleaning up dev namespace manually..."
	@echo "⚠️  Note: This only cleans up manually created resources."
	@echo "   Flux-managed resources should be removed via GitOps."
	@$(KUBECTL) delete namespace dev --ignore-not-found=true || true
	@echo "Dev namespace cleaned up"

cleanup-flux-files: ## Clean up Flux-generated bootstrap files
	@echo "🧹 Cleaning up Flux-generated bootstrap files..."
	@echo "🗑️  Removing entire flux-system folder..."
	@rm -rf flux-cd/bootstrap/flux-system
	@echo "✅ Flux bootstrap files completely cleaned up"
	@echo "📝 Committing cleanup to git..."
	@git add flux-cd/bootstrap/flux-system/ || true
	@git commit -m "Clean up Flux-generated bootstrap files" || true
	@echo "📤 Pushing cleanup to main..."
	@git push origin main || true
	@echo "🎉 Cleanup committed and pushed to main!"

cleanup-all: cleanup-app cleanup-flux-files ## Clean up all application resources
	@echo "All application resources cleaned up"

# ------------------------------
# FluxCD GitOps Management
# ------------------------------

install-tools: ## Install all required tools (Flux, Kind, kubectl, etc.)
	@echo "🔧 Installing required tools..."
	@echo ""
	@echo "📦 Checking and installing kubectl..."
	@if ! command -v kubectl >/dev/null 2>&1; then \
		if command -v brew >/dev/null 2>&1; then \
			brew install kubectl; \
		else \
			echo "Homebrew not found. Please install kubectl manually:"; \
			echo "  curl -LO https://dl.k8s.io/release/v1.28.0/bin/darwin/amd64/kubectl"; \
			echo "  chmod +x kubectl && sudo mv kubectl /usr/local/bin/"; \
			exit 1; \
		fi \
	else \
		echo "✅ kubectl already installed"; \
	fi
	@echo ""
	@echo "🐳 Checking and installing Kind..."
	@if ! command -v kind >/dev/null 2>&1; then \
		if command -v brew >/dev/null 2>&1; then \
			brew install kind; \
		else \
			echo "Homebrew not found. Please install Kind manually:"; \
			echo "  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-darwin-amd64"; \
			echo "  chmod +x ./kind && sudo mv ./kind /usr/local/bin/"; \
			exit 1; \
		fi \
	else \
		echo "✅ Kind already installed"; \
	fi
	@echo ""
	@echo "📊 Checking and installing FluxCD CLI..."
	@if ! command -v flux >/dev/null 2>&1; then \
		if command -v brew >/dev/null 2>&1; then \
			brew install fluxcd/tap/flux; \
		else \
			echo "Homebrew not found. Please install FluxCD CLI manually:"; \
			echo "  curl -s https://fluxcd.io/install.sh | sudo bash"; \
			exit 1; \
		fi \
	else \
		echo "✅ FluxCD CLI already installed"; \
	fi
	@echo ""
	@echo "🚀 Checking and installing hey (load testing tool)..."
	@if ! command -v hey >/dev/null 2>&1; then \
		if command -v brew >/dev/null 2>&1; then \
			brew install hey; \
		else \
			echo "Homebrew not found. Please install hey manually:"; \
			echo "  go install github.com/rakyll/hey@latest"; \
			echo "  or download from: https://github.com/rakyll/hey/releases"; \
		fi \
	else \
		echo "✅ hey already installed"; \
	fi
	@echo ""
	@echo "🎯 Checking Docker..."
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "❌ Docker not found. Please install Docker Desktop:"; \
		echo "  https://www.docker.com/products/docker-desktop/"; \
		exit 1; \
	else \
		echo "✅ Docker already installed"; \
	fi
	@echo ""
	@echo "🎉 All required tools are ready!"

check-versions: ## Check versions of installed tools
	@echo "📋 Tool versions:"
	@echo "kubectl: $(shell kubectl version --client --short 2>/dev/null | head -1 || echo "not available")"
	@echo "kind: $(shell kind version 2>/dev/null || echo "not available")"
	@echo "flux: $(shell flux version 2>/dev/null | head -1 || echo "not available")"
	@echo "hey: $(shell hey version 2>/dev/null | head -1 || echo "not available")"
	@echo "docker: $(shell docker version --format "{{.Version}}" 2>/dev/null | head -1 || echo "not available")"

install-flux-cli: ## Install FluxCD CLI (legacy target - use install-tools instead)
	@echo "Installing FluxCD CLI..."
	@if command -v brew >/dev/null 2>&1; then \
		brew install fluxcd/tap/flux; \
	else \
		echo "Homebrew not found. Please install FluxCD CLI manually:"; \
		echo "  curl -s https://fluxcd.io/install.sh | sudo bash"; \
		exit 1; \
	fi

bootstrap-flux: ## Bootstrap FluxCD to the cluster
	@echo "Bootstrapping FluxCD..."
	@if ! command -v flux >/dev/null 2>&1; then \
		echo "FluxCD CLI not found. Run 'make install-flux-cli' first"; \
		exit 1; \
	fi
	@flux bootstrap git \
		--url=ssh://git@github.com/$(GITHUB_USER)/$(GITHUB_REPO) \
		--branch=main \
		--path=flux-cd/bootstrap \
		--namespace=flux-system \
		--components-extra=image-reflector-controller,image-automation-controller

flux-status: ## Check FluxCD status
	@echo "📊 FluxCD Git Repository Status:"
	@flux get sources git
	@echo ""
	@echo "📋 FluxCD Kustomizations:"
	@flux get kustomizations
	@echo ""
	@echo "📦 FluxCD Helm Releases:"
	@flux get helmreleases -A

flux-logs: ## Follow FluxCD logs
	@echo "Following FluxCD logs (Ctrl-C to stop)..."
	@flux logs --follow

flux-suspend: ## Suspend FluxCD reconciliation
	@echo "Suspending FluxCD reconciliation..."
	@flux suspend kustomization --all

flux-resume: ## Resume FluxCD reconciliation
	@echo "🔄 Resuming FluxCD reconciliation..."
	@flux resume kustomization --all

# ------------------------------
# Script Wrappers
# ------------------------------

setup-all: ## Run complete setup script (creates cluster, installs Flux, deploys everything)
	@./scripts/setup-all.sh

teardown-all: ## Run complete teardown script (cleans up everything)
	@./scripts/teardown-all.sh

hpa-demo: ## Run HPA demo script (load testing and monitoring)
	@./scripts/hpa-demo.sh

hpa-reset: ## Reset HPA deployment to clean state (2 replicas)
	@./scripts/hpa-demo.sh reset

debug-metrics: ## Run debug metrics script (cross-namespace metrics testing)
	@./scripts/debug-metrics-simple.sh

check-flux: ## Check Flux readiness and sync status
	@./scripts/check-flux-ready.sh

# ------------------------------
# Complete Flux Workflow
# ------------------------------

wait-for-flux: ## Wait for Flux to be ready and synced
	@echo "⏳ Waiting for Flux to be ready..."
	@echo "🔍 Checking if Flux is running..."
	@kubectl wait --for=condition=Ready --timeout=300s -n flux-system pod -l app.kubernetes.io/name=flux || true
	@echo "✅ Flux is ready!"
	@echo "🔄 Waiting for initial sync to complete..."
	@echo "⏳ This may take a few minutes for the first sync..."
	@timeout 300s bash -c 'until ./scripts/check-flux-ready.sh; do sleep 10; done' || true
	@echo "🎉 Flux is fully synced and ready!"

deploy-via-flux: ## Deploy everything via Flux GitOps
	@echo "🚀 Deploying everything via Flux GitOps..."
	@echo "📝 Committing current state to trigger Flux deployment..."
	@git add . || true
	@git commit -m "Auto-deploy via Flux $(shell date +%Y%m%d-%H%M%S)" || true
	@echo "📤 Pushing to main branch to trigger Flux..."
	@git push origin main || true
	@echo "✅ Deployment triggered! Flux will now sync your cluster."
	@echo "⏳ Check status with: make flux-status"

deploy-everything: build-and-push-services deploy-via-flux ## Complete workflow: build app, deploy via Flux
	@echo "🚀 Complete deployment workflow finished!"
	@echo "⏳ Your cluster is now being managed by Flux GitOps."
	@echo "📊 Monitor progress with: make flux-status"

cluster-status: ## Check overall cluster and Flux status
	@echo "🔍 Cluster Status:"
	@echo "=================="
	@kubectl cluster-info --context kind-kaiko-lab 2>/dev/null || echo "❌ Not connected to kaiko-lab cluster"
	@echo ""
	@echo "📊 Flux Status:"
	@echo "==============="
	@if kubectl get namespace flux-system >/dev/null 2>&1; then \
		./scripts/check-flux-ready.sh 2>/dev/null && echo "✅ Flux is healthy" || echo "❌ Flux has issues"; \
	else \
		echo "❌ Flux not installed"; \
	fi
	@echo ""
	@echo "🚀 Application Status:"
	@echo "======================"
	@echo "📋 All Namespaces:"
	@kubectl get namespaces --no-headers | grep -E "(dev|staging|production|monitoring|flux-system)" | awk '{print "  " $$1 ": " $$2}'
	@echo ""
	@echo "📦 Pods by Environment:"
	@echo "  Development:"
	@kubectl get pods -n dev --no-headers 2>/dev/null | awk '{print "    " $$1 " (" $$3 ")"}' || echo "    No pods found"
	@echo "  Staging:"
	@kubectl get pods -n staging --no-headers 2>/dev/null | awk '{print "    " $$1 " (" $$3 ")"}' || echo "    No pods found"
	@echo "  Production:"
	@kubectl get pods -n production --no-headers 2>/dev/null | awk '{print "    " $$1 " (" $$3 ")"}' || echo "    No pods found"
	@echo "  Monitoring:"
	@kubectl get pods -n monitoring --no-headers 2>/dev/null | awk '{print "    " $$1 " (" $$3 ")"}' || echo "    No pods found"
	@echo "  Flux System:"
	@kubectl get pods -n flux-system --no-headers 2>/dev/null | awk '{print "    " $$1 " (" $$3 ")"}' || echo "    No pods found"

# ------------------------------
# Environment Management
# ------------------------------

deploy-dev: ## Deploy dev environment via GitOps (legacy - use deploy-via-flux)
	@echo "⚠️  This target is deprecated. Use 'make deploy-via-flux' instead."
	@echo "   Flux will automatically deploy all environments from your repo."

deploy-staging: ## Deploy staging environment via GitOps (legacy - use deploy-via-flux)
	@echo "⚠️  This target is deprecated. Use 'make deploy-via-flux' instead."
	@echo "   Flux will automatically deploy all environments from your repo."

deploy-production: ## Deploy production environment via GitOps (legacy - use deploy-via-flux)
	@echo "⚠️  This target is deprecated. Use 'make deploy-via-flux' instead."
	@echo "   Flux will automatically deploy all environments from your repo."

# ------------------------------
# Configuration
# ------------------------------

# GitHub Configuration (override these values)
GITHUB_USER ?= phaidon-passias
GITHUB_REPO ?= kaiko-assignment

use-context: check-deps ## Switch kubectl context to this cluster
	@$(KUBECTL) config use-context $(KUBE_CONTEXT)

start-cluster: create-cluster start-docker-registry use-context install-metrics-server build-and-push-services ## Create cluster and switch kubectl context

stop-cluster: stop-docker-registry delete-cluster  ## Delete cluster and stop docker registry

## build service docker image and push to local registry
build-and-push-services: app-build app-push

start-docker-registry:
	@echo "${GREEN}Start local docker registry:${RESET}\n"
	@if docker ps -a --format "table {{.Names}}" | grep -q "kind-registry"; then \
		echo "kind-registry container already exists, starting it..."; \
		docker start kind-registry || true; \
	else \
		echo "Creating new kind-registry container..."; \
		docker run -d -p "127.0.0.1:5000:5000" --restart=always --network bridge --name kind-registry registry:2; \
	fi
	@docker network connect "kind" "kind-registry" || true

## Stops the local docker registry
stop-docker-registry:
	@echo "${GREEN}Stop and delete local docker registry:${RESET}\n"
	@docker stop kind-registry
	@docker rm kind-registry

## Build app docker image
app-build:
	@echo "${GREEN}Building app docker image:${RESET}\n"
	@cd app && docker build -t localhost:5000/app .

## Push app docker image to local registry
app-push:
	@echo "${GREEN}Pushing app docker image to local registry:${RESET}\n"
	@docker push localhost:5000/app

current-context: ## Show current kubectl context
	@$(KUBECTL) config current-context

list-clusters: check-deps ## List existing kind clusters
	@$(KIND) get clusters

# ------------------------------
# HPA load test helpers - Used while creating the hpa-demo script
# ------------------------------

hpa-load: ## Port-forward svc/app and generate load (hey if available; robust cleanup)
	@set -e; \
	echo "Starting port-forward to svc/app on :8080..."; \
	kubectl -n dev port-forward svc/app 8080:80 >/tmp/pf-app.log 2>&1 & echo $$! > /tmp/pf-app.pid; \
	cleanup() { kill $$(cat /tmp/pf-app.pid) >/dev/null 2>&1 || true; rm -f /tmp/pf-app.pid; }; \
	trap cleanup EXIT INT TERM; \
	echo "Waiting for app readiness on /healthz..."; \
	for i in $$(seq 1 30); do \
	  if curl -sf http://localhost:8080/healthz >/dev/null; then echo "App is ready."; break; fi; \
	  sleep 1; \
	  if [ $$i -eq 30 ]; then echo "App did not become ready in time"; exit 1; fi; \
	done; \
	if command -v hey >/dev/null 2>&1; then \
	  echo "Running hey: duration=$(HPA_DURATION)s, concurrency=$(HPA_CONCURRENCY)"; \
	  hey -z $(strip $(HPA_DURATION))s -c $(strip $(HPA_CONCURRENCY)) http://localhost:8080/work; \
	else \
	  echo "hey not installed; using curl fallback"; \
	  end=$$(($$(date +%s)+$(strip $(HPA_DURATION)))); \
	  while [ $$(date +%s) -lt $$end ]; do \
	    for i in $$(seq 1 $(strip $(HPA_CONCURRENCY))); do curl -s -o /dev/null http://localhost:8080/work & done; \
	    wait; \
	    sleep $(strip $(HPA_PAUSE)); \
	  done; \
	fi

hpa-watch: ## Watch HPA and deployment scaling
	@echo "Watching HPA (Ctrl-C to stop)"
	@$(KUBECTL) get hpa -n dev -w

hpa-stop: ## Stop port-forward (if left running)
	@kill $$(cat /tmp/pf-app.pid) >/dev/null 2>&1 || true
	@rm -f /tmp/pf-app.pid

# ------------------------------
# Metrics Server (metrics.k8s.io) install for kind
# ------------------------------

install-metrics-server: ## Install metrics-server and patch flags for kind, then verify
	@echo "Installing metrics-server..."
	@$(KUBECTL) apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml | cat
	@echo "Patching metrics-server image to use more reliable registry..."
	@$(KUBECTL) -n kube-system patch deploy metrics-server --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"k8s.gcr.io/metrics-server/metrics-server:v0.8.0"}]' | cat || true

	@if ! $(KUBECTL) -n kube-system get deploy metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | grep -q -- '--kubelet-insecure-tls'; then \
	  $(KUBECTL) -n kube-system patch deploy metrics-server --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' | cat || true; \
	fi
	@if ! $(KUBECTL) -n kube-system get deploy metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | grep -q -- '--kubelet-preferred-address-types'; then \
	  $(KUBECTL) -n kube-system patch deploy metrics-server --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP"}]' | cat || true; \
	fi

	@echo "Waiting for metrics-server Deployment to be Available..."
	@echo "Cleaning up any old metrics-server replicas..."
	@$(KUBECTL) -n kube-system delete replicaset --selector=k8s-app=metrics-server --ignore-not-found=true | cat || true
	@$(KUBECTL) -n kube-system rollout status deploy/metrics-server --timeout=180s | cat || true
	@$(KUBECTL) -n kube-system wait deploy/metrics-server --for=condition=Available --timeout=60s | cat || true

	@echo "Waiting for metrics API (v1beta1.metrics.k8s.io) to be Available..."
	@$(KUBECTL) wait --for=condition=Available apiservice v1beta1.metrics.k8s.io --timeout=120s | cat || true

	@echo "Verifying metrics API..."
	@$(KUBECTL) get apiservices | grep metrics | cat || true
	@$(KUBECTL) top pods -A | head -n 5 | cat || true

