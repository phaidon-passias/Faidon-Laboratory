#!/usr/bin/env bash
set -euo pipefail

# Simple script to check if Flux is ready and synced
# Used by other scripts to ensure Flux is working before proceeding

echo "🔍 Checking Flux readiness..."

# Check if Flux namespace exists
if ! kubectl get namespace flux-system >/dev/null 2>&1; then
    echo "❌ Flux namespace not found. Flux is not installed."
    exit 1
fi

# Check if Flux pods are running
if ! kubectl get pods -n flux-system --no-headers | grep -E "(helm-controller|kustomize-controller|notification-controller|source-controller)" | grep -q "Running"; then
    echo "❌ Flux pods are not running. Flux is not ready."
    exit 1
fi

# Check if Flux has synced at least once
SYNC_STATUS=$(flux get kustomizations --no-header | grep -c "True" || echo "0")
if [ "$SYNC_STATUS" -eq 0 ]; then
    echo "❌ Flux has not completed initial sync yet."
    exit 1
fi

echo "✅ Flux is ready and synced!"
exit 0
