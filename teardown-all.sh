#!/usr/bin/env bash
set -euo pipefail

# Teardown with Flux:
# - Suspends Flux reconciliation
# - Cleans up application resources
# - Stops port-forward if any
# - Deletes kind cluster and local registry

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "🔄 [1/5] Suspending Flux reconciliation..."
make -C "$ROOT_DIR" flux-suspend || true

echo "🧹 [2/5] Cleaning up application resources..."
make -C "$ROOT_DIR" cleanup-all || true

echo "🛑 [3/5] Stopping any lingering port-forward..."
if [ -f /tmp/pf-app.pid ]; then
  kill "$(cat /tmp/pf-app.pid)" >/dev/null 2>&1 || true
  rm -f /tmp/pf-app.pid
fi

echo "🗑️  [4/5] Deleting kind cluster..."
make -C "$ROOT_DIR" delete-cluster || true

echo "🛑 [5/5] Stopping local docker registry..."
make -C "$ROOT_DIR" stop-docker-registry || true

echo "✅ Teardown complete. Flux has been suspended and cluster cleaned up."
