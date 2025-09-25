#!/bin/bash

# Test OTEL Pipeline Script
# This script generates telemetry data and helps verify the pipeline is working

set -e

echo "🚀 Testing OTEL Pipeline"
echo "========================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

print_status "Connected to Kubernetes cluster"

# Get Alloy service details
ALLOY_SERVICE=$(kubectl get svc -n monitoring | grep alloy | awk '{print $1}' || echo "")
if [ -z "$ALLOY_SERVICE" ]; then
    print_error "Alloy service not found in monitoring namespace"
    exit 1
fi

ALLOY_IP=$(kubectl get svc -n monitoring $ALLOY_SERVICE -o jsonpath='{.spec.clusterIP}')
ALLOY_OTLP_GRPC_PORT=$(kubectl get svc -n monitoring $ALLOY_SERVICE -o jsonpath='{.spec.ports[?(@.name=="grpc-otlp")].port}')
ALLOY_OTLP_HTTP_PORT=$(kubectl get svc -n monitoring $ALLOY_SERVICE -o jsonpath='{.spec.ports[?(@.name=="http-otlp")].port}')

print_success "Found Alloy service: $ALLOY_SERVICE"
print_status "Alloy OTLP GRPC endpoint: $ALLOY_IP:$ALLOY_OTLP_GRPC_PORT"
print_status "Alloy OTLP HTTP endpoint: $ALLOY_IP:$ALLOY_OTLP_HTTP_PORT"

# Function to generate test metrics via HTTP OTLP
generate_test_metrics() {
    local namespace=$1
    local app_name=$2
    
    print_status "Generating test metrics for $app_name in namespace $namespace"
    
    # Create a simple metric payload
    cat << EOF | kubectl run -i --rm --restart=Never test-metrics-$app_name-$namespace \
        --image=curlimages/curl:latest \
        --namespace=$namespace \
        -- curl -X POST \
        http://$ALLOY_SERVICE.monitoring.svc.cluster.local:$ALLOY_OTLP_HTTP_PORT/v1/metrics \
        -H "Content-Type: application/json" \
        -d '{
            "resourceMetrics": [{
                "resource": {
                    "attributes": [{
                        "key": "service.name",
                        "value": {"stringValue": "'$app_name'"}
                    }, {
                        "key": "k8s.namespace.name", 
                        "value": {"stringValue": "'$namespace'"}
                    }]
                },
                "scopeMetrics": [{
                    "scope": {"name": "test-scope"},
                    "metrics": [{
                        "name": "test_metric_total",
                        "description": "Test metric for OTEL pipeline validation",
                        "unit": "1",
                        "sum": {
                            "dataPoints": [{
                                "timeUnixNano": "'$(date +%s)000000000'",
                                "asInt": "1"
                            }],
                            "aggregationTemporality": "AGGREGATION_TEMPORALITY_CUMULATIVE",
                            "isMonotonic": true
                        }
                    }]
                }]
            }]
        }'
EOF
}

# Function to generate test logs via HTTP OTLP
generate_test_logs() {
    local namespace=$1
    local app_name=$2
    
    print_status "Generating test logs for $app_name in namespace $namespace"
    
    cat << EOF | kubectl run -i --rm --restart=Never test-logs-$app_name-$namespace \
        --image=curlimages/curl:latest \
        --namespace=$namespace \
        -- curl -X POST \
        http://$ALLOY_SERVICE.monitoring.svc.cluster.local:$ALLOY_OTLP_HTTP_PORT/v1/logs \
        -H "Content-Type: application/json" \
        -d '{
            "resourceLogs": [{
                "resource": {
                    "attributes": [{
                        "key": "service.name",
                        "value": {"stringValue": "'$app_name'"}
                    }, {
                        "key": "k8s.namespace.name",
                        "value": {"stringValue": "'$namespace'"}
                    }]
                },
                "scopeLogs": [{
                    "scope": {"name": "test-scope"},
                    "logRecords": [{
                        "timeUnixNano": "'$(date +%s)000000000'",
                        "severityNumber": 9,
                        "severityText": "INFO",
                        "body": {"stringValue": "Test log message from '$app_name' in namespace '$namespace' - OTEL pipeline test"},
                        "attributes": [{
                            "key": "test.type",
                            "value": {"stringValue": "otel-pipeline-validation"}
                        }]
                    }]
                }]
            }]
        }'
EOF
}

# Function to check if applications are running
check_applications() {
    print_status "Checking application pods..."
    
    # Check dev namespace
    if kubectl get pods -n dev | grep -q "demo-app-go.*Running"; then
        print_success "Go app in dev namespace is running"
        generate_test_metrics "dev" "demo-app-go"
        generate_test_logs "dev" "demo-app-go"
    else
        print_warning "Go app in dev namespace is not running"
    fi
    
    if kubectl get pods -n dev | grep -q "demo-app-python.*Running"; then
        print_success "Python app in dev namespace is running"
        generate_test_metrics "dev" "demo-app-python"
        generate_test_logs "dev" "demo-app-python"
    else
        print_warning "Python app in dev namespace is not running"
    fi
    
    # Check staging namespace
    if kubectl get pods -n staging | grep -q "demo-app-go.*Running"; then
        print_success "Go app in staging namespace is running"
        generate_test_metrics "staging" "demo-app-go"
        generate_test_logs "staging" "demo-app-go"
    else
        print_warning "Go app in staging namespace is not running"
    fi
    
    if kubectl get pods -n staging | grep -q "demo-app-python.*Running"; then
        print_success "Python app in staging namespace is running"
        generate_test_metrics "staging" "demo-app-python"
        generate_test_logs "staging" "demo-app-python"
    else
        print_warning "Python app in staging namespace is not running"
    fi
    
    # Check production namespace
    if kubectl get pods -n production | grep -q "demo-app-go.*Running"; then
        print_success "Go app in production namespace is running"
        generate_test_metrics "production" "demo-app-go"
        generate_test_logs "production" "demo-app-go"
    else
        print_warning "Go app in production namespace is not running"
    fi
    
    if kubectl get pods -n production | grep -q "demo-app-python.*Running"; then
        print_success "Python app in production namespace is running"
        generate_test_metrics "production" "demo-app-python"
        generate_test_logs "production" "demo-app-python"
    else
        print_warning "Python app in production namespace is not running"
    fi
}

# Function to setup port forwarding for Grafana
setup_grafana_access() {
    print_status "Setting up Grafana access..."
    
    # Check if Grafana service exists
    if ! kubectl get svc -n monitoring | grep -q grafana; then
        print_error "Grafana service not found"
        return 1
    fi
    
    print_success "Grafana service found"
    print_status "To access Grafana UI, run:"
    echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    echo ""
    print_status "Then open: http://localhost:3000"
    print_status "Default credentials: admin / admin"
    echo ""
}

# Function to check Prometheus metrics
check_prometheus_metrics() {
    print_status "Checking Prometheus for test metrics..."
    
    # Get Prometheus service
    PROMETHEUS_SERVICE=$(kubectl get svc -n monitoring | grep prometheus | grep -v alertmanager | awk '{print $1}' || echo "")
    if [ -z "$PROMETHEUS_SERVICE" ]; then
        print_error "Prometheus service not found"
        return 1
    fi
    
    print_success "Prometheus service found: $PROMETHEUS_SERVICE"
    print_status "To query Prometheus directly, run:"
    echo "  kubectl port-forward -n monitoring svc/$PROMETHEUS_SERVICE 9090:9090"
    echo ""
    print_status "Then open: http://localhost:9090"
    print_status "Try querying: test_metric_total"
    echo ""
}

# Function to check Alloy logs
check_alloy_logs() {
    print_status "Checking Alloy logs for processing activity..."
    
    echo "Recent Alloy logs:"
    kubectl logs -n monitoring deployment/grafana-alloy -c alloy --tail=20
    echo ""
}

# Main execution
main() {
    echo ""
    print_status "Starting OTEL Pipeline Test"
    echo ""
    
    # Check applications and generate test data
    check_applications
    
    echo ""
    print_status "Waiting 10 seconds for data to be processed..."
    sleep 10
    
    # Check Alloy logs
    check_alloy_logs
    
    # Setup access instructions
    setup_grafana_access
    check_prometheus_metrics
    
    echo ""
    print_success "OTEL Pipeline Test Complete!"
    echo ""
    print_status "Next steps:"
    echo "1. Access Grafana UI to verify metrics are visible"
    echo "2. Check Prometheus UI to see raw metrics"
    echo "3. Look for custom labels: environment, cluster_name, collector"
    echo "4. Verify metrics from different namespaces have correct environment labels"
    echo ""
}

# Run main function
main "$@"
