#!/usr/bin/env bash
set -euo pipefail

# Teardown:
# - Deletes app namespace (app resources)
# - Stops port-forward if any
# - Deletes kind cluster and local registry

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "[1/4] Cleaning up application resources..."
make -C "$ROOT_DIR" cleanup-all || true

echo "[2/4] Stopping any lingering port-forward..."
if [ -f /tmp/pf-app.pid ]; then
  kill "$(cat /tmp/pf-app.pid)" >/dev/null 2>&1 || true
  rm -f /tmp/pf-app.pid
fi

echo "[3/4] Deleting kind cluster..."
make -C "$ROOT_DIR" delete-cluster || true

echo "[4/4] Stopping local docker registry..."
make -C "$ROOT_DIR" stop-docker-registry || true

echo "Teardown complete."
