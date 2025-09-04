#!/bin/bash

# Debug Metrics Script - Simplified Version
# Creates a debug pod and tests the metrics endpoint

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Configuration
DEBUG_POD_NAME="debug-metrics-simple"
DEBUG_NAMESPACE="monitoring"
APP_NAMESPACE="dev"
APP_SERVICE="app"
METRICS_PORT="80"
DEBUG_IMAGE="nicolaka/netshoot"

print_header "Debug Metrics Endpoint Test - Simplified"
print_status "Debug namespace: $DEBUG_NAMESPACE"
print_status "Target namespace: $APP_NAMESPACE"
print_status "Target service: $APP_SERVICE"
print_status "Metrics port: $METRICS_PORT"

# Check if namespaces exist
if ! kubectl get namespace $DEBUG_NAMESPACE &> /dev/null; then
    print_error "Namespace '$DEBUG_NAMESPACE' does not exist"
    exit 1
fi

if ! kubectl get namespace $APP_NAMESPACE &> /dev/null; then
    print_error "Namespace '$APP_NAMESPACE' does not exist"
    exit 1
fi

# Check if app service exists
if ! kubectl get service -n $APP_NAMESPACE $APP_SERVICE &> /dev/null; then
    print_error "Service '$APP_SERVICE' in namespace '$APP_NAMESPACE' does not exist"
    exit 1
fi

# Check if app pods are running
print_status "Checking app pod status..."
if ! kubectl get pods -n $APP_NAMESPACE --field-selector=status.phase=Running | grep -q .; then
    print_warning "No running pods found in namespace '$APP_NAMESPACE'"
    exit 1
fi

print_status "App pods are running"

# Check if debug pod already exists
print_header "Debug Pod Setup"
if kubectl get pod -n $DEBUG_NAMESPACE $DEBUG_POD_NAME &> /dev/null; then
    POD_STATUS=$(kubectl get pod -n $DEBUG_NAMESPACE $DEBUG_POD_NAME --no-headers | awk '{print $3}')
    
    if [ "$POD_STATUS" = "Running" ]; then
        print_status "Debug pod '$DEBUG_POD_NAME' already exists and is running, reusing it..."
    elif [ "$POD_STATUS" = "Completed" ] || [ "$POD_STATUS" = "Failed" ] || [ "$POD_STATUS" = "Error" ]; then
        print_status "Debug pod '$DEBUG_POD_NAME' exists but is in '$POD_STATUS' status, deleting and recreating..."
        kubectl delete pod -n $DEBUG_NAMESPACE $DEBUG_POD_NAME
        print_status "Creating new debug pod '$DEBUG_POD_NAME' in namespace '$DEBUG_NAMESPACE'..."
        kubectl run $DEBUG_POD_NAME \
            -n $DEBUG_NAMESPACE \
            --image=$DEBUG_IMAGE \
            --restart=Never \
            -- sleep 300
        kubectl wait --for=condition=Ready pod/$DEBUG_POD_NAME -n $DEBUG_NAMESPACE --timeout=60s
    else
        print_status "Debug pod '$DEBUG_POD_NAME' exists but is in '$POD_STATUS' status, waiting for it to be ready..."
        kubectl wait --for=condition=Ready pod/$DEBUG_POD_NAME -n $DEBUG_NAMESPACE --timeout=60s
    fi
else
    print_status "Creating new debug pod '$DEBUG_POD_NAME' in namespace '$DEBUG_NAMESPACE'..."
    
    kubectl run $DEBUG_POD_NAME \
        -n $DEBUG_NAMESPACE \
        --image=$DEBUG_IMAGE \
        --restart=Never \
        -- sleep 300
    
    # Wait for debug pod to be ready
    print_status "Waiting for debug pod to be ready..."
    kubectl wait --for=condition=Ready pod/$DEBUG_POD_NAME -n $DEBUG_NAMESPACE --timeout=60s
fi

print_status "Debug pod is ready"

# Check pod status
print_status "Debug pod details:"
kubectl get pod -n $DEBUG_NAMESPACE $DEBUG_POD_NAME -o wide

# Wait a moment for pod to be fully ready
print_status "Waiting for pod to be fully ready..."
sleep 5

# Test connectivity
print_header "Testing Connectivity"

print_status "Testing DNS resolution..."
kubectl exec -n $DEBUG_NAMESPACE $DEBUG_POD_NAME -- nslookup $APP_SERVICE.$APP_NAMESPACE.svc.cluster.local

print_status "Testing service connectivity..."
kubectl exec -n $DEBUG_NAMESPACE $DEBUG_POD_NAME -- curl -s http://$APP_SERVICE.$APP_NAMESPACE.svc.cluster.local:$METRICS_PORT/healthz

# Test metrics endpoint
print_header "Testing Metrics Endpoint"

print_status "Fetching metrics from $APP_SERVICE.$APP_NAMESPACE.svc.cluster.local:$METRICS_PORT/metrics..."

# Get metrics and format output
METRICS_OUTPUT=$(kubectl exec -n $DEBUG_NAMESPACE $DEBUG_POD_NAME -- curl -s http://$APP_SERVICE.$APP_NAMESPACE.svc.cluster.local:$METRICS_PORT/metrics)

if [ $? -eq 0 ] && [ -n "$METRICS_OUTPUT" ]; then
    print_status "Metrics endpoint is accessible!"
    
    # Show metrics summary
    print_header "Metrics Summary"
    echo "$METRICS_OUTPUT" | grep -E "^[^#]" | head -20
    
    # Count total metrics
    METRICS_COUNT=$(echo "$METRICS_OUTPUT" | grep -E "^[^#]" | wc -l)
    print_status "Total metrics available: $METRICS_COUNT"
    
    # Show specific app metrics if they exist
    if echo "$METRICS_OUTPUT" | grep -q "app_"; then
        print_status "Application-specific metrics found:"
        echo "$METRICS_OUTPUT" | grep "app_" | head -10
    fi
    
    # Show HTTP metrics if they exist
    if echo "$METRICS_OUTPUT" | grep -q "http_"; then
        print_status "HTTP metrics found:"
        echo "$METRICS_OUTPUT" | grep "http_" | head -10
    fi
    
else
    print_error "Failed to fetch metrics from endpoint"
fi

# Additional debugging information
print_header "Additional Debug Information"

print_status "Service details:"
kubectl get service -n $APP_NAMESPACE $APP_SERVICE -o wide

print_status "Pod endpoints:"
kubectl get endpoints -n $APP_NAMESPACE $APP_SERVICE

print_status "Network policies:"
kubectl get networkpolicies -n $APP_NAMESPACE || print_warning "No network policies found"

print_header "Debug Complete"
print_status "Debug pod is still running in namespace '$DEBUG_NAMESPACE'"
print_status "To manually access the debug pod:"
echo "  kubectl exec -it -n $DEBUG_NAMESPACE $DEBUG_POD_NAME -- /bin/bash"
print_status "To clean up the debug pod:"
echo "  kubectl delete pod -n $DEBUG_NAMESPACE $DEBUG_POD_NAME"
print_status "Note: The pod will be reused on subsequent runs unless manually deleted"
