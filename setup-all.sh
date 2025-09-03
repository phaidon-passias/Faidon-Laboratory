#!/usr/bin/env bash
set -euo pipefail

# End-to-end setup:
# - Creates kind cluster (and local registry)
# - Installs metrics-server
# - Builds and pushes app image to localhost:5000
# - Applies Kubernetes manifests and waits for rollout

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "[1/5] Ensuring kind cluster and metrics-server..."
make -C "$ROOT_DIR" start-cluster

echo "[2/5] Building and pushing app image..."
make -C "$ROOT_DIR" build-and-push-services

echo "[3/5] Applying manifests..."
kubectl apply -f "$ROOT_DIR/kubernetes_manifests/app.yaml"

echo "[4/5] Waiting for rollout..."
kubectl -n app rollout status deploy/app --timeout=180s

echo "[5/5] Verifying resources..."
kubectl -n app get all

echo "Setup complete. You can now run: ./hpa-demo.sh run"


