## Makefile for managing a local Kubernetes cluster with kind

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

.DEFAULT_GOAL := help
.PHONY: help check-deps create-cluster delete-cluster use-context cluster current-context list-clusters install-monitoring

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  %-22s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

check-deps: ## Verify required CLI tools are installed
	@command -v $(KIND) >/dev/null 2>&1 || { echo "ERROR: kind not found. Install from https://kind.sigs.k8s.io/"; exit 1; }
	@command -v $(KUBECTL) >/dev/null 2>&1 || { echo "ERROR: kubectl not found. Install kubectl first."; exit 1; }

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

debug-container:
	@$(KUBECTL) run -n default toolbox --rm -it --image=nicolaka/netshoot --restart=Never -- sh 

delete-cluster: check-deps ## Delete the kind cluster and delete port forwards
	@$(KIND) delete cluster --name $(CLUSTER_NAME)
	lsof -iTCP -sTCP:LISTEN -n -P
	@echo "Killing all open port forward sessions created by user. You can go ahead and create a new cluster"
	pkill -f "kubectl.*port-forward" 2>&1;

use-context: check-deps ## Switch kubectl context to this cluster
	@$(KUBECTL) config use-context $(KUBE_CONTEXT)

cluster: create-cluster use-context ## Create cluster and switch kubectl context

current-context: ## Show current kubectl context
	@$(KUBECTL) config current-context

list-clusters: check-deps ## List existing kind clusters
	@$(KIND) get clusters
