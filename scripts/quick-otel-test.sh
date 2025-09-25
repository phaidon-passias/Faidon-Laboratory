#!/bin/bash

# Quick OTEL Pipeline Test
# Simple script to generate test data and check the pipeline

set -e

echo "🚀 Quick OTEL Pipeline Test"
echo "=========================="

# Get Alloy service details
ALLOY_SERVICE=$(kubectl get svc -n monitoring | grep alloy | awk '{print $1}')
ALLOY_HTTP_PORT=$(kubectl get svc -n monitoring $ALLOY_SERVICE -o jsonpath='{.spec.ports[?(@.name=="http-otlp")].port}')

echo "📡 Alloy OTLP HTTP endpoint: $ALLOY_SERVICE.monitoring.svc.cluster.local:$ALLOY_HTTP_PORT"

# Generate a simple test metric
echo "📊 Generating test metric..."

kubectl run -i --rm --restart=Never quick-test-metric \
    --image=curlimages/curl:latest \
    --namespace=dev \
    -- curl -X POST \
    http://$ALLOY_SERVICE.monitoring.svc.cluster.local:$ALLOY_HTTP_PORT/v1/metrics \
    -H "Content-Type: application/json" \
    -d '{
        "resourceMetrics": [{
            "resource": {
                "attributes": [{
                    "key": "service.name",
                    "value": {"stringValue": "quick-test"}
                }, {
                    "key": "k8s.namespace.name", 
                    "value": {"stringValue": "dev"}
                }]
            },
            "scopeMetrics": [{
                "scope": {"name": "quick-test"},
                "metrics": [{
                    "name": "quick_test_metric",
                    "description": "Quick test metric",
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

echo ""
echo "✅ Test metric sent!"
echo ""
echo "🔍 To verify the pipeline:"
echo "1. Check Alloy logs: kubectl logs -n monitoring deployment/grafana-alloy -c alloy --tail=10"
echo "2. Access Grafana: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "3. Access Prometheus: kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
echo ""
echo "🎯 Look for:"
echo "- Custom labels: environment=dev, cluster_name=kind-cluster, collector=alloy"
echo "- Metric name: quick_test_metric"
