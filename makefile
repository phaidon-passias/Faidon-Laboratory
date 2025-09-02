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

.DEFAULT_GOAL := help
.PHONY: help check-deps create-cluster delete-cluster use-context cluster current-context list-clusters install-monitoring

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  %-22s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

check-deps: ## Verify required CLI tools are installed
	@command -v $(KIND) >/dev/null 2>&1 || { echo "ERROR: kind not found. Install from https://kind.sigs.k8s.io/"; exit 1; }
	@command -v $(KUBECTL) >/dev/null 2>&1 || { echo "ERROR: kubectl not found. Install kubectl first."; exit 1; }
	@PORT=5000; \
	if lsof -iTCP:$${PORT} -sTCP:LISTEN -n -P >/dev/null 2>&1; then \
	  echo "ERROR: Port $${PORT} is already in use on the host."; \
	  echo "This blocks the local registry (localhost:$${PORT})."; \
	  echo "Close the process using port $${PORT} (on macOS, often AirPlay Receiver) and rerun the command."; \
	  echo "Hint (macOS): System Settings → General → AirDrop & Handoff → AirPlay Receiver → Off"; \
	  exit 1; \
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

debug-container:
	@$(KUBECTL) run -n default toolbox --rm -it --image=nicolaka/netshoot --restart=Never -- sh 

delete-cluster: check-deps ## Delete the kind cluster and delete port forwards
	@$(KIND) delete cluster --name $(CLUSTER_NAME)
	lsof -iTCP -sTCP:LISTEN -n -P

use-context: check-deps ## Switch kubectl context to this cluster
	@$(KUBECTL) config use-context $(KUBE_CONTEXT)

start-cluster: create-cluster start-docker-registry use-context ## Create cluster and switch kubectl context

stop-cluster: stop-docker-registry delete-cluster  ## Delete cluster and stop docker registry

## build service docker image and push to local registry
build-and-push-services: app-build app-push

start-docker-registry:
	@echo "${GREEN}Start local docker registry:${RESET}\n"
	@docker run -d -p "127.0.0.1:5000:5000" --restart=always --network bridge --name kind-registry registry:2  
	@docker network connect "kind" "kind-registry"

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

