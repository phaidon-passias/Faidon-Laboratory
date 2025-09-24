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

# Setup progress tracking
SETUP_PROGRESS_FILE="/tmp/demo-app-python-setup-progress"
STEP_COMPLETED="✅"
STEP_SKIPPED="⏭️ "
STEP_FAILED="❌"

# Function to mark step as completed
mark_step_completed() {
    echo "$1" >> "$SETUP_PROGRESS_FILE"
}

# Function to check if step is completed
is_step_completed() {
    [ -f "$SETUP_PROGRESS_FILE" ] && grep -q "^$1$" "$SETUP_PROGRESS_FILE"
}

# Function to wait for resource with timeout
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-default}"
    local timeout="${4:-300}"
    
    echo "⏳ Waiting for $resource_type/$resource_name in namespace $namespace (timeout: ${timeout}s)..."
    
    if kubectl wait --for=condition=Ready "$resource_type/$resource_name" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        echo "✅ $resource_type/$resource_name is ready"
        return 0
    else
        echo "⚠️  $resource_type/$resource_name not ready within ${timeout}s, continuing..."
        return 1
    fi
}

# Function to wait for deployment with timeout and smart verification
wait_for_deployment() {
    local deployment_name="$1"
    local namespace="${2:-default}"
    local timeout="${3:-300}"
    
    echo "⏳ Waiting for deployment/$deployment_name in namespace $namespace (timeout: ${timeout}s)..."
    
    # First try the standard rollout status - handle both deployments and statefulsets
    local rollout_success=false
    if kubectl get deployment "$deployment_name" -n "$namespace" >/dev/null 2>&1; then
        if kubectl rollout status deployment/"$deployment_name" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
            echo "✅ deployment/$deployment_name is ready"
            return 0
        fi
    elif kubectl get statefulset "$deployment_name" -n "$namespace" >/dev/null 2>&1; then
        if kubectl rollout status statefulset/"$deployment_name" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
            echo "✅ statefulset/$deployment_name is ready"
            return 0
        fi
    else
        echo "⚠️  Neither deployment nor statefulset $deployment_name found in namespace $namespace"
        return 1
    fi
    
    if [ "$rollout_success" = false ]; then
        echo "⚠️  deployment/$deployment_name not ready within ${timeout}s, doing final verification..."
        
        # Smart final check: be more patient and check pod status directly
        echo "   🔍 Final verification: checking if pods are actually ready..."
        
        # Wait a bit more and check multiple times
        for i in {1..6}; do
            echo "   ⏳ Attempt $i/6: waiting 30s and checking pod status..."
            sleep 30
            
            # Check deployment/statefulset status
            local ready_replicas="0"
            local desired_replicas="0"
            if kubectl get deployment "$deployment_name" -n "$namespace" >/dev/null 2>&1; then
                ready_replicas=$(kubectl get deployment "$deployment_name" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
                desired_replicas=$(kubectl get deployment "$deployment_name" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
            elif kubectl get statefulset "$deployment_name" -n "$namespace" >/dev/null 2>&1; then
                ready_replicas=$(kubectl get statefulset "$deployment_name" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
                desired_replicas=$(kubectl get statefulset "$deployment_name" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
            fi
            
            echo "   📊 Current status: ${ready_replicas}/${desired_replicas} replicas ready"
            
            # Also check pod status directly - handle both deployments and statefulsets
            local pod_status=""
            if kubectl get deployment "$deployment_name" -n "$namespace" >/dev/null 2>&1; then
                # It's a deployment, use deployment labels
                pod_status=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name="$deployment_name" -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "")
            elif kubectl get statefulset "$deployment_name" -n "$namespace" >/dev/null 2>&1; then
                # It's a statefulset, use statefulset labels
                pod_status=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name="$deployment_name" -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "")
            else
                # Try to find pods by name pattern
                pod_status=$(kubectl get pods -n "$namespace" | grep "$deployment_name" | awk '{print $3}' | tr '\n' ' ' || echo "")
            fi
            echo "   🏃 Pod phases: $pod_status"
            
            if [ "$ready_replicas" = "$desired_replicas" ] && [ "$ready_replicas" != "0" ]; then
                echo "✅ deployment/$deployment_name is actually ready (${ready_replicas}/${desired_replicas} replicas)"
                return 0
            fi
        done
        
        echo "⚠️  deployment/$deployment_name still not ready after extended wait, continuing..."
        return 1
    fi
}

# Step 1: Ensure kind cluster and metrics-server
if ! is_step_completed "step1-cluster"; then
    echo "🚀 [1/7] Ensuring kind cluster and metrics-server..."
    
    # Check if port 5000 is in use by kind-registry (allow it)
    if lsof -i :5000 >/dev/null 2>&1; then
        if docker ps --format "table {{.Names}}" | grep -q "kind-registry"; then
            echo "ℹ️  Port 5000 is in use by kind-registry, continuing..."
        else
            echo "⚠️  Port 5000 is in use by another process. Attempting to continue..."
        fi
    fi
    
    cd "$ROOT_DIR" && make start-cluster
    mark_step_completed "step1-cluster"
else
    echo "$STEP_SKIPPED [1/7] Kind cluster and metrics-server already set up"
fi

# Step 2: Install all required tools
if ! is_step_completed "step2-tools"; then
    echo "🔧 [2/7] Installing all required tools..."
    cd "$ROOT_DIR" && make install-tools
    mark_step_completed "step2-tools"
else
    echo "$STEP_SKIPPED [2/7] All tools already installed"
fi

# Step 3: Install and bootstrap Flux
if ! is_step_completed "step3-flux-bootstrap"; then
    echo "⚡ [3/7] Installing and bootstrapping Flux..."
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

    # Install Flux components (only if not already installed)
    echo "   🔧 Installing Flux components..."
    if kubectl get namespace flux-system >/dev/null 2>&1; then
        echo "   ℹ️  Flux is already installed, skipping installation..."
    else
        echo "   🔧 Installing Flux components..."
        flux install --version=v2.6.4
    fi

    # Bootstrap Flux with Git repository (only if not already bootstrapped)
    echo "   🚀 Bootstrapping Flux with Git repository..."
    if kubectl get gitrepository flux-system -n flux-system >/dev/null 2>&1; then
        echo "   ℹ️  Flux is already bootstrapped, skipping bootstrap..."
    else
        echo "   🚀 Bootstrapping Flux with Git repository..."
        flux bootstrap git --url=ssh://git@github.com/phaidon-passias/Faidon-Laboratory --branch=main --path=flux-cd/bootstrap --namespace=flux-system
    fi

    echo "   ⏳ Waiting for Flux controllers to be ready..."
    wait_for_deployment "helm-controller" "flux-system" 300
    wait_for_deployment "kustomize-controller" "flux-system" 300
    wait_for_deployment "notification-controller" "flux-system" 300
    wait_for_deployment "source-controller" "flux-system" 300
    
    mark_step_completed "step3-flux-bootstrap"
else
    echo "$STEP_SKIPPED [3/7] Flux already bootstrapped"
fi

# Step 4: Validate kustomizations
if ! is_step_completed "step4-validate"; then
    echo "🔍 [4/7] Validating kustomizations..."
    cd "$ROOT_DIR" && make kustomize-check
    mark_step_completed "step4-validate"
else
    echo "$STEP_SKIPPED [4/7] Kustomizations already validated"
fi

# Step 5: Build and push app image
if ! is_step_completed "step5-build-push"; then
    echo "🏗️  [5/7] Building and pushing app image..."
    cd "$ROOT_DIR" && make build-and-push-services
    mark_step_completed "step5-build-push"
else
    echo "$STEP_SKIPPED [5/7] App image already built and pushed"
fi

# Step 6: Deploy everything via Flux GitOps
if ! is_step_completed "step6-deploy"; then
    echo "🚀 [6/7] Deploying everything via Flux GitOps..."
    cd "$ROOT_DIR" && make deploy-via-flux
    
    echo "   ⏳ Waiting for Prometheus stack to be ready..."
    
    # First, wait for Flux to actually deploy the resources
    echo "   🔄 Waiting for Flux to deploy Prometheus stack resources..."
    max_wait=300
    waited=0
    while [ $waited -lt $max_wait ]; do
        if kubectl get deployment kube-prometheus-stack-grafana -n monitoring >/dev/null 2>&1; then
            echo "   ✅ Prometheus stack resources detected, proceeding with readiness checks..."
            break
        fi
        echo "   ⏳ Waiting for Prometheus stack resources to be deployed... (${waited}s/${max_wait}s)"
        sleep 10
        waited=$((waited + 10))
    done
    
    if [ $waited -ge $max_wait ]; then
        echo "   ⚠️  Prometheus stack resources not deployed within ${max_wait}s, continuing anyway..."
    fi
    
    # Now wait for the deployments to be ready
    wait_for_deployment "kube-prometheus-stack-grafana" "monitoring" 600
    wait_for_deployment "kube-prometheus-stack-operator" "monitoring" 600
    
    # Additional wait for Prometheus server (it often takes longer)
    echo "   ⏳ Waiting for Prometheus server to be ready..."
    wait_for_deployment "prometheus-kube-prometheus-stack-prometheus" "monitoring" 300
    
    # Final comprehensive check
    echo "   🔍 Final verification: checking all Prometheus stack components..."
    sleep 10
    kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-stack
    
    mark_step_completed "step6-deploy"
else
    echo "$STEP_SKIPPED [6/7] Applications already deployed"
fi

# Step 7: Final verification
echo "⏳ [7/7] Final verification and cleanup..."
echo "📊 Check status with: make flux-status"
echo "📊 Watch logs with: make flux-logs"

# Clear progress file on successful completion
rm -f "$SETUP_PROGRESS_FILE"

echo "🎉 Setup complete! Your cluster is now managed by Flux GitOps."
echo ""
echo "📝 Next Steps:"
echo "=============="
echo ""
echo "🔍 1. Verify Deployment:"
echo "   make cluster-status    # Check overall cluster and application status"
echo "   make flux-status       # Check GitOps (Flux) satus"
echo ""
echo "🧪 2. Test Application Functionality:"
echo "   make debug-metrics     # Test cross-namespace metrics and monitoring"
echo "   make hpa-demo          # Demonstrate HPA with load testing"
echo ""
echo "📊 3. Access Monitoring UI:"
echo "   # Grafana (monitoring dashboard)"
echo "   kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80"
echo "   # Then open: http://localhost:3000 (admin/admin)"
echo ""
echo "   # Prometheus (metrics database)"
echo "   kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
echo "   # Then open: http://localhost:9090 (admin/prom-operator)"
echo ""
echo "🧹 4. Cleanup (when done):"
echo "   make teardown-all      # Complete environment cleanup"
echo ""
echo "📚 5. Documentation:"
echo "   - See how-to-run.MD for detailed instructions"
echo "   - See scripts/SCRIPTS.md for script documentation"
echo "   - See SOLUTION.md for technical implementation details"


