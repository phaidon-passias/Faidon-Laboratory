#!/usr/bin/env bash
set -euo pipefail

# Teardown with Flux:
# - Suspends Flux reconciliation
# - Cleans up application resources
# - Stops port-forward if any
# - Deletes kind cluster and local registry

# Get the root directory (parent of scripts directory)
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

echo "🔄 [1/5] Suspending Flux reconciliation..."
cd "$ROOT_DIR" && make flux-suspend || true

echo "🧹 [2/5] Cleaning up application resources and Flux files..."
echo "   This will also commit and push the cleanup to main..."
cd "$ROOT_DIR" && make cleanup-all || true

echo "🛑 [3/5] Stopping any lingering port-forward..."
if [ -f /tmp/pf-app.pid ]; then
  kill "$(cat /tmp/pf-app.pid)" >/dev/null 2>&1 || true
  rm -f /tmp/pf-app.pid
fi

echo "🛑 [4/5] Stopping local docker registry..."
cd "$ROOT_DIR" && make stop-docker-registry || true

echo "🗑️  [5/5] Deleting kind cluster..."
cd "$ROOT_DIR" && make delete-cluster || true

echo "✅ Teardown complete. Flux has been suspended and cluster cleaned up."
