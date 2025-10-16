#!/bin/bash

# Verify Grafana Dashboard Integration
# This script checks if the dashboards are properly deployed and accessible

set -e

echo "🔍 Verifying Grafana Dashboard Integration..."

# Check if Grafana is running
echo "📊 Checking Grafana deployment status..."
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Check if dashboard ConfigMap exists
echo "📋 Checking dashboard ConfigMap..."
kubectl get configmap grafana-dashboards -n monitoring

# Check if dashboard files are mounted
echo "📁 Checking dashboard files in Grafana pod..."
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
if [ -n "$GRAFANA_POD" ]; then
    echo "Grafana pod: $GRAFANA_POD"
    kubectl exec -n monitoring $GRAFANA_POD -- ls -la /var/lib/grafana/dashboards/default/
else
    echo "❌ No Grafana pod found"
    exit 1
fi

# Check Grafana logs for dashboard loading
echo "📝 Checking Grafana logs for dashboard loading..."
kubectl logs -n monitoring $GRAFANA_POD | grep -i dashboard || echo "No dashboard-related logs found"

# Port forward to access Grafana UI
echo "🌐 Setting up port forward to Grafana (http://localhost:3000)..."
echo "Username: admin, Password: admin"
echo "Press Ctrl+C to stop port forwarding"

kubectl port-forward -n monitoring svc/lgtm-stack-grafana 3000:80
