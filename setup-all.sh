#!/usr/bin/env bash
set -euo pipefail

# End-to-end setup with Flux GitOps:
# - Creates kind cluster (and local registry)
# - Installs metrics-server
# - Bootstraps Flux and waits for readiness
# - Builds and pushes app image to localhost:5000
# - Deploys everything via Flux GitOps

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "🚀 [1/6] Ensuring kind cluster and metrics-server..."
make -C "$ROOT_DIR" start-cluster

echo "🔧 [2/6] Installing Flux CLI..."
make -C "$ROOT_DIR" install-flux-cli

echo "⚡ [3/6] Bootstrapping Flux and waiting for readiness..."
make -C "$ROOT_DIR" setup-flux

echo "🏗️  [4/6] Building and pushing app image..."
make -C "$ROOT_DIR" build-and-push-services

echo "🚀 [5/6] Deploying everything via Flux GitOps..."
make -C "$ROOT_DIR" deploy-via-flux

echo "⏳ [6/6] Waiting for Flux to complete deployment..."
echo "📊 Check status with: make flux-status"
echo "📊 Watch logs with: make flux-logs"

echo "🎉 Setup complete! Your cluster is now managed by Flux GitOps."
echo "📝 Next steps:"
echo "   - Monitor deployment: make flux-status"
echo "   - Run HPA demo: ./hpa-demo.sh run"
echo "   - Check monitoring: kubectl get all -n monitoring"


