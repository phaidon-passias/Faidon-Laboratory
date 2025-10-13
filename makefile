## Makefile for managing a local Kubernetes cluster with kind
GREEN = \033[1;32m
RESET = \033[0m
WHITE = \033[1;38;5;231m
BLUE = \033[1;34m
YELLOW = \033[1;33m
RED = \033[1;31m

# ------------------------------
# Configurable variables (override via: make CLUSTER_NAME=mycluster)
# ------------------------------
CLUSTER_NAME ?= demo-app-python-lab
K8S_VERSION ?= v1.29.2
KIND_NODE_IMAGE ?= kindest/node:$(K8S_VERSION)
KIND ?= kind
KUBECTL ?= kubectl
KUBE_CONTEXT ?= kind-$(CLUSTER_NAME)
CREATE_WAIT ?= 120s
KIND_CONFIG ?= scripts/kind-three-node.yaml
HPA_DURATION ?= 120        # seconds
HPA_CONCURRENCY ?= 200      # parallel clients
HPA_PAUSE ?= 0.1

# Resource configuration for different environments
DEV_CPU_REQUEST ?= 50m
DEV_CPU_LIMIT ?= 200m
DEV_MEMORY_REQUEST ?= 64Mi
DEV_MEMORY_LIMIT ?= 128Mi
DEV_REPLICAS ?= 1

STAGING_CPU_REQUEST ?= 100m
STAGING_CPU_LIMIT ?= 300m
STAGING_MEMORY_REQUEST ?= 128Mi
STAGING_MEMORY_LIMIT ?= 256Mi
STAGING_REPLICAS ?= 2

PROD_CPU_REQUEST ?= 200m
PROD_CPU_LIMIT ?= 500m
PROD_MEMORY_REQUEST ?= 256Mi
PROD_MEMORY_LIMIT ?= 512Mi
PROD_REPLICAS ?= 3    

.DEFAULT_GOAL := help
.PHONY: help check-deps create-cluster delete-cluster use-context cluster current-context list-clusters hpa-load hpa-watch install-metrics deploy-everything install-tools check-versions setup-all teardown-all hpa-demo hpa-reset debug-metrics check-flux kustomize-build kustomize-validate kustomize-lint kustomize-structure environment-status

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

cleanup-all: cleanup-flux-files ## Clean up all application resources
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
	@echo "🔄 Checking and installing kubectx (kubectl context switcher)..."
	@if ! command -v kubectx >/dev/null 2>&1; then \
		if command -v brew >/dev/null 2>&1; then \
			brew install kubectx; \
		else \
			echo "Homebrew not found. Please install kubectx manually:"; \
			echo "  curl -L https://github.com/ahmetb/kubectx/releases/latest/download/kubectx -o kubectx"; \
			echo "  chmod +x kubectx && sudo mv kubectx /usr/local/bin/"; \
		fi \
	else \
		echo "✅ kubectx already installed"; \
	fi
	@echo ""
	@echo "🔍 Checking and installing kustomize..."
	@if ! command -v kustomize >/dev/null 2>&1; then \
		if command -v brew >/dev/null 2>&1; then \
			brew install kustomize; \
		else \
			echo "Homebrew not found. Please install kustomize manually:"; \
			echo "  curl -s \"https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh\" | bash"; \
			echo "  sudo mv kustomize /usr/local/bin/"; \
		fi \
	else \
		echo "✅ kustomize already installed"; \
	fi
	@echo ""
	@echo "🔧 Checking and installing kubeconform..."
	@if ! command -v kubeconform >/dev/null 2>&1; then \
		echo "Installing kubeconform from GitHub releases..."; \
		ARCH=$$(uname -m); \
		OS=$$(uname -s); \
		if [ "$$OS" = "Darwin" ]; then \
			if [ "$$ARCH" = "arm64" ]; then \
				curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-darwin-arm64.tar.gz | tar xz; \
			else \
				curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-darwin-amd64.tar.gz | tar xz; \
			fi; \
		else \
			curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz; \
		fi; \
		chmod +x kubeconform; \
		sudo mv kubeconform /usr/local/bin/; \
		rm -f LICENSE; \
		echo "✅ kubeconform installed successfully"; \
	else \
		echo "✅ kubeconform already installed"; \
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
	@echo "kubectl: $(shell kubectl version --client 2>/dev/null | grep "Client Version" | awk '{print $$3}' || echo "not available")"
	@echo "kind: $(shell kind version 2>/dev/null || echo "not available")"
	@echo "flux: $(shell flux version --client 2>/dev/null | sed 's/flux: //' || echo "not available")"
	@echo "hey: $(shell command -v hey >/dev/null 2>&1 && echo "installed" || echo "not available")"
	@echo "kubectx: $(shell command -v kubectx >/dev/null 2>&1 && echo "installed" || echo "not available")"
	@echo "kustomize: $(shell kustomize version 2>/dev/null | head -1 || echo "not available")"
	@echo "kubeconform: $(shell kubeconform -v 2>/dev/null | head -1 || echo "not available")"
	@echo "docker: $(shell docker version 2>/dev/null | grep "Version:" | head -1 | awk '{print $$2}' || echo "not available")"

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
	@echo "📥 Pulling latest changes from main..."
	@git pull origin main || true
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
	@kubectl cluster-info --context kind-demo-app-python-lab 2>/dev/null || echo "❌ Not connected to demo-app-python-lab cluster"
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
GITHUB_REPO ?= Faidon-Laboratory

use-context: check-deps ## Switch kubectl context to this cluster
	@$(KUBECTL) config use-context $(KUBE_CONTEXT)

start-cluster: create-cluster start-docker-registry use-context install-metrics-server build-and-push-services ## Create cluster and switch kubectl context

stop-cluster: stop-docker-registry delete-cluster  ## Delete cluster and stop docker registry

## build service docker image and push to local registry
build-and-push-services: python-build python-push go-build go-push notification-build notification-push

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

## Build Python app docker image
python-build:
	@echo "${GREEN}Building Python app docker image:${RESET}\n"
	@cp -r shared-libraries applications/user-service/
	@cd applications/user-service && docker build -t localhost:5000/user-service:latest .
	@rm -rf applications/user-service/shared-libraries

## Push Python app docker image to local registry
python-push:
	@echo "${GREEN}Pushing Python app docker image to local registry:${RESET}\n"
	@docker push localhost:5000/user-service:latest

## Build Go app docker image
go-build:
	@echo "${GREEN}Building Go app docker image:${RESET}\n"
	@cp -r shared-libraries applications/api-gateway/
	@cd applications/api-gateway && docker build -t localhost:5000/api-gateway:latest .
	@rm -rf applications/api-gateway/shared-libraries

## Push Go app docker image to local registry
go-push:
	@echo "${GREEN}Pushing Go app docker image to local registry:${RESET}\n"
	@docker push localhost:5000/api-gateway:latest

## Build Notification service docker image
notification-build:
	@echo "${GREEN}Building Notification service docker image:${RESET}\n"
	@cp -r shared-libraries applications/notification-service/
	@cd applications/notification-service && docker build -t localhost:5000/notification-service:latest .
	@rm -rf applications/notification-service/shared-libraries

## Push Notification service docker image to local registry
notification-push:
	@echo "${GREEN}Pushing Notification service docker image to local registry:${RESET}\n"
	@docker push localhost:5000/notification-service:latest

## Legacy targets for backward compatibility
app-build: python-build
app-push: python-push

## Individual app build targets
build-python: python-build python-push ## Build and push only Python app
build-go: go-build go-push ## Build and push only Go app
build-notification: notification-build notification-push ## Build and push only Notification service
build-all: build-and-push-services ## Build and push all services

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

# ------------------------------
# Kustomize Validation & Linting
# ------------------------------

KUSTOMIZE ?= kustomize
KUBECONFORM ?= kubeconform

kustomize-build: ## Build all kustomizations and show output
	@echo "🔨 Building all kustomizations..."
	@echo ""
	@echo "📦 Infrastructure:"
	@echo "=================="
	@$(KUSTOMIZE) build flux-cd/infrastructure
	@echo ""
	@echo "🚀 Applications:"
	@echo "================"
	@$(KUSTOMIZE) build flux-cd/applications
	@echo ""
	@echo "⚡ Bootstrap:"
	@echo "============="
	@$(KUSTOMIZE) build flux-cd/bootstrap

kustomize-validate: ## Validate kustomizations with kubeconform (if available)
	@echo "🔍 Validating kustomizations with kubeconform..."
	@if command -v $(KUBECONFORM) >/dev/null 2>&1; then \
		echo "✅ kubeconform found, validating..."; \
		echo ""; \
		echo "🌳 Validating Complete Tree (Bootstrap):"; \
		$(KUSTOMIZE) build flux-cd/bootstrap | $(KUBECONFORM) -strict -ignore-missing-schemas || echo "❌ Complete tree validation failed"; \
		echo ""; \
		echo "📦 Validating Infrastructure (standalone):"; \
		$(KUSTOMIZE) build flux-cd/infrastructure | $(KUBECONFORM) -strict -ignore-missing-schemas || echo "❌ Infrastructure validation failed"; \
		echo ""; \
		echo "🚀 Validating Applications (standalone):"; \
		$(KUSTOMIZE) build flux-cd/applications | $(KUBECONFORM) -strict -ignore-missing-schemas || echo "❌ Applications validation failed"; \
	else \
		echo "⚠️  kubeconform not found. Install with: make install-tools"; \
	fi

kustomize-lint: ## Lint kustomizations with kubeconform (if available)
	@echo "🔍 Linting kustomizations with kubeconform..."
	@if command -v $(KUBECONFORM) >/dev/null 2>&1; then \
		echo "✅ kubeconform found, linting..."; \
		echo ""; \
		echo "📦 Linting Infrastructure:"; \
		$(KUSTOMIZE) build flux-cd/infrastructure | $(KUBECONFORM) -strict -ignore-missing-schemas || echo "❌ Infrastructure linting failed"; \
		echo ""; \
		echo "🚀 Linting Applications:"; \
		$(KUSTOMIZE) build flux-cd/applications | $(KUBECONFORM) -strict -ignore-missing-schemas || echo "❌ Applications linting failed"; \
		echo ""; \
		echo "⚡ Linting Bootstrap:"; \
		$(KUSTOMIZE) build flux-cd/bootstrap | $(KUBECONFORM) -strict -ignore-missing-schemas || echo "❌ Bootstrap linting failed"; \
	else \
		echo "⚠️  kubeconform not found. Install with: make install-tools"; \
	fi

kustomize-structure: ## Show kustomization structure and count
	@echo "📊 Kustomization Structure Analysis:"
	@echo "===================================="
	@echo ""
	@echo "🔍 Finding all kustomization.yaml files..."
	@echo ""
	@echo "📦 Infrastructure Kustomizations:"
	@echo "=================================="
	@find flux-cd/infrastructure -name "kustomization.yaml" -type f | while read file; do \
		dir=$$(dirname "$$file"); \
		name=$$(grep "^metadata:" -A 5 "$$file" | grep "name:" | awk '{print $$2}' || echo "unnamed"); \
		resources=$$(grep "^resources:" -A 20 "$$file" | grep "^- " | wc -l | tr -d ' '); \
		echo "  📁 $$dir"; \
		echo "     Name: $$name"; \
		echo "     Resources: $$resources"; \
		echo ""; \
	done
	@echo "🚀 Application Kustomizations:"
	@echo "=============================="
	@find flux-cd/applications -name "kustomization.yaml" -type f | while read file; do \
		dir=$$(dirname "$$file"); \
		name=$$(grep "^metadata:" -A 5 "$$file" | grep "name:" | awk '{print $$2}' || echo "unnamed"); \
		resources=$$(grep "^resources:" -A 20 "$$file" | grep "^- " | wc -l | tr -d ' '); \
		echo "  📁 $$dir"; \
		echo "     Name: $$name"; \
		echo "     Resources: $$resources"; \
		echo ""; \
	done
	@echo "⚡ Bootstrap Kustomizations:"
	@echo "============================"
	@find flux-cd/bootstrap -name "kustomization.yaml" -type f | while read file; do \
		dir=$$(dirname "$$file"); \
		name=$$(grep "^metadata:" -A 5 "$$file" | grep "name:" | awk '{print $$2}' || echo "unnamed"); \
		resources=$$(grep "^resources:" -A 20 "$$file" | grep "^- " | wc -l | tr -d ' '); \
		echo "  📁 $$dir"; \
		echo "     Name: $$name"; \
		echo "     Resources: $$resources"; \
		echo ""; \
	done
	@echo "📈 Summary:"
	@echo "==========="
	@total_kustomizations=$$(find flux-cd -name "kustomization.yaml" -type f | wc -l | tr -d ' '); \
	echo "  Total Kustomizations: $$total_kustomizations"; \
	total_resources=$$(find flux-cd -name "*.yaml" -not -name "kustomization.yaml" -type f | wc -l | tr -d ' '); \
	echo "  Total Resource Files: $$total_resources"

kustomize-check: kustomize-structure kustomize-build ## Complete kustomize check (structure + build)
	@echo ""
	@echo "✅ Kustomize check completed successfully!"
	@echo "   All kustomizations built without errors."

install-linters: ## Install kustomize validation tools
	@echo "🔧 Installing kustomize validation tools..."
	@echo ""
	@echo "📦 Installing kubeconform..."
	@if ! command -v kubeconform >/dev/null 2>&1; then \
		echo "Installing kubeconform from GitHub releases..."; \
		ARCH=$$(uname -m); \
		OS=$$(uname -s); \
		if [ "$$OS" = "Darwin" ]; then \
			if [ "$$ARCH" = "arm64" ]; then \
				curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-darwin-arm64.tar.gz | tar xz; \
			else \
				curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-darwin-amd64.tar.gz | tar xz; \
			fi; \
		else \
			curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz; \
		fi; \
		chmod +x kubeconform; \
		sudo mv kubeconform /usr/local/bin/; \
		rm -f LICENSE; \
		echo "✅ kubeconform installed successfully"; \
	else \
		echo "✅ kubeconform already installed"; \
	fi
	@echo ""
	@echo "🎉 All kustomize validation tools are ready!"

# ------------------------------
# Environment Status & Validation
# ------------------------------

environment-status: ## Show detailed status of all environments
	@echo "${BLUE}🌍 Environment Status Overview${RESET}"
	@echo "================================"
	@echo ""
	@for env in dev staging production; do \
		echo "${YELLOW}📋 Environment: $$env${RESET}"; \
		echo "-------------------"; \
		if kubectl get namespace $$env >/dev/null 2>&1; then \
			echo "✅ Namespace exists"; \
			pod_count=$$(kubectl get pods -n $$env --no-headers 2>/dev/null | wc -l); \
			ready_pods=$$(kubectl get pods -n $$env --no-headers 2>/dev/null | grep -c "Running" || echo "0"); \
			echo "📦 Pods: $$ready_pods/$$pod_count ready"; \
			echo "🔧 Services:"; \
			kubectl get services -n $$env --no-headers 2>/dev/null | awk '{print "  - " $$1 " (" $$2 ")"}' || echo "  No services found"; \
			echo "🌐 Network Policies:"; \
			kubectl get networkpolicies -n $$env --no-headers 2>/dev/null | awk '{print "  - " $$1}' || echo "  No network policies found"; \
		else \
			echo "❌ Namespace $$env not found"; \
		fi; \
		echo ""; \
	done


