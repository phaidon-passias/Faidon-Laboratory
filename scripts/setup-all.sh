#!/usr/bin/env bash
set -euo pipefail

# End-to-end setup with Flux GitOps:
# - Creates kind cluster (and local registry)
# - Installs metrics-server
# - Installs Flux components and bootstraps with Git repository
# - Builds and pushes app image to localhost:5000
# - Deploys everything via Flux GitOps
#
# ⚠️  IMPORTANT: During bootstrap, Flux will generate an SSH key.
#     You'll need to add this key to your GitHub repository as a Deploy Key.
#     The script will show you the key and instructions at the end.

# Get the root directory (parent of scripts directory)
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

echo "🚀 [1/6] Ensuring kind cluster and metrics-server..."
cd "$ROOT_DIR" && make start-cluster

echo "🔧 [2/6] Installing Flux CLI..."
cd "$ROOT_DIR" && make install-flux-cli

echo "⚡ [3/6] Installing and bootstrapping Flux..."
echo "   📝 Note: This process will:"
echo "      - Pull latest changes from main"
echo "      - Clean up any existing flux-system folder"
echo "      - Install Flux components directly in the cluster"
echo "      - Bootstrap Flux with your Git repository"
echo "      - Wait for Flux to be ready"

# Pull latest changes from main
echo "   📥 Pulling latest changes from main..."
cd "$ROOT_DIR" && git pull origin main

# Remove the flux-system folder if it exists (to avoid conflicts)
echo "   🗑️  Cleaning up any existing flux-system folder..."
cd "$ROOT_DIR" && rm -rf flux-cd/bootstrap/flux-system

# Install Flux components
echo "   🔧 Installing Flux components..."
flux install --version=v2.6.4

# Bootstrap Flux with Git repository
echo "   🚀 Bootstrapping Flux with Git repository..."
flux bootstrap git --url=ssh://git@github.com/phaidon-passias/kaiko-assignment --branch=main --path=flux-cd/bootstrap --namespace=flux-system

echo "   ⏳ Waiting for Flux to be ready..."
cd "$ROOT_DIR" && make wait-for-flux

echo "🏗️  [4/6] Building and pushing app image..."
cd "$ROOT_DIR" && make build-and-push-services

echo "🚀 [5/6] Deploying everything via Flux GitOps..."
cd "$ROOT_DIR" && make deploy-via-flux

echo "⏳ [6/6] Waiting for Flux to complete deployment..."
echo "📊 Check status with: make flux-status"
echo "📊 Watch logs with: make flux-logs"

echo "🎉 Setup complete! Your cluster is now managed by Flux GitOps."
echo "📝 Next steps:"
echo "   - Monitor deployment: make flux-status"
echo "   - Run HPA demo: ./scripts/hpa-demo.sh run"
echo "   - Check monitoring: kubectl get all -n monitoring"
echo ""
echo "⚠️  IMPORTANT: If this is a fresh setup, you'll need to add the Flux SSH key to your GitHub repository:"
echo "   1. Go to your repo → Settings → Deploy keys"
echo "   2. Add the public key shown during bootstrap"
echo "   3. Check 'Allow write access'"
echo "   4. Click 'Add key'"


