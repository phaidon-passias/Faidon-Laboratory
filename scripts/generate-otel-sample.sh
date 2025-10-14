#!/usr/bin/env bash
set -euo pipefail

# Generator for traces, logs, and metrics through our services and Alloy → Tempo/Loki
# - Traces: HTTP OTLP to Alloy's OTLP HTTP (4318) + trigger our services
# - Logs: create sample logs + trigger our services in multiple namespaces
# - Metrics: trigger our services to generate metrics

NAMESPACES=("dev" "staging" "production")
ALLOY_OTLP_HTTP="http://lgtm-stack-tempo-distributor.monitoring.svc.cluster.local:4318"

echo "[generate-otel-sample] Generating samples across namespaces: ${NAMESPACES[*]}"
echo "[generate-otel-sample] OTLP HTTP endpoint: ${ALLOY_OTLP_HTTP}"
echo ""

# Function to generate samples in a specific namespace
generate_samples_in_namespace() {
    local namespace="$1"
    local timestamp=$(date +%s)
    
    echo "[generate-otel-sample] === Processing namespace: ${namespace} ==="
    
    # Check if namespace exists
    if ! kubectl get namespace "${namespace}" >/dev/null 2>&1; then
        echo "[generate-otel-sample] ⚠️  Namespace ${namespace} does not exist, skipping..."
        return
    fi
    
    # Create HTTP OTLP trace
    echo "[generate-otel-sample] Creating trace via HTTP OTLP in ${namespace}..."
    kubectl -n "${namespace}" run "otel-http-trace-${namespace}-$$" \
      --image=curlimages/curl:latest \
      --restart=Never \
      --command -- sh -c \
      "curl -X POST ${ALLOY_OTLP_HTTP}/v1/traces \
        -H 'Content-Type: application/json' \
        -d '{
          \"resourceSpans\": [{
            \"resource\": {
              \"attributes\": [{
                \"key\": \"service.name\",
                \"value\": {\"stringValue\": \"generate-otel-sample-${namespace}\"}
              }, {
                \"key\": \"namespace\",
                \"value\": {\"stringValue\": \"${namespace}\"}
              }]
            },
            \"scopeSpans\": [{
              \"spans\": [{
                \"traceId\": \"$(openssl rand -hex 16)\",
                \"spanId\": \"$(openssl rand -hex 8)\",
                \"name\": \"generate-otel-sample-span-${namespace}\",
                \"kind\": 1,
                \"startTimeUnixNano\": \"${timestamp}000000000\",
                \"endTimeUnixNano\": \"$((${timestamp} + 1))000000000\",
                \"attributes\": [{
                  \"key\": \"env\",
                  \"value\": {\"stringValue\": \"${namespace}\"}
                }, {
                  \"key\": \"test.type\",
                  \"value\": {\"stringValue\": \"generated-sample\"}
                }]
              }]
            }]
          }]
        }' \
        && echo 'HTTP trace sent to ${namespace}'; sleep 1" || echo "Failed to create trace in ${namespace}"
    
    # Trigger services if they exist in this namespace
    echo "[generate-otel-sample] Triggering services in ${namespace}..."
    kubectl -n "${namespace}" run "service-trigger-${namespace}-$$" \
      --image=curlimages/curl:latest \
      --restart=Never \
      --command -- sh -c \
      "echo 'Triggering API Gateway /process-user endpoint in ${namespace}...' && \
       curl -X POST http://api-gateway-${namespace}.${namespace}.svc.cluster.local:8080/process-user \
         -H 'Content-Type: application/json' \
         -d '{\"user_id\":\"test-user-${namespace}\",\"action\":\"create\",\"message\":\"Test message from generate-otel-sample in ${namespace}\"}' \
         -s || echo 'API Gateway process-user failed in ${namespace}' && \
       echo 'Triggering user-service health check in ${namespace}...' && \
       curl -s http://user-service-${namespace}.${namespace}.svc.cluster.local:8000/health || echo 'user-service health check failed in ${namespace}' && \
       echo 'Triggering notification-service health check in ${namespace}...' && \
       curl -s http://notification-service-${namespace}.${namespace}.svc.cluster.local:8000/health || echo 'notification-service health check failed in ${namespace}' && \
       echo 'All service calls completed in ${namespace}'; sleep 2" || echo "Failed to trigger services in ${namespace}"
    
    # Generate sample logs
    echo "[generate-otel-sample] Emitting sample logs in ${namespace}..."
    kubectl -n "${namespace}" run "log-generator-${namespace}-$$" \
      --image=busybox \
      --restart=Never \
      --command -- sh -c \
      "for i in \$(seq 1 5); do echo \"{\\\"level\\\":\\\"INFO\\\",\\\"message\\\":\\\"demo log \$i from ${namespace}\\\",\\\"component\\\":\\\"generator\\\",\\\"namespace\\\":\\\"${namespace}\\\"}\"; sleep 1; done" || echo "Failed to create log generator in ${namespace}"
    
    # Clean up pods after a short delay
    sleep 3
    kubectl -n "${namespace}" delete pod "otel-http-trace-${namespace}-$$" --ignore-not-found 2>/dev/null || true
    kubectl -n "${namespace}" delete pod "service-trigger-${namespace}-$$" --ignore-not-found 2>/dev/null || true
    kubectl -n "${namespace}" delete pod "log-generator-${namespace}-$$" --ignore-not-found 2>/dev/null || true
    
    echo "[generate-otel-sample] ✓ Completed samples for ${namespace}"
    echo ""
}

# Generate samples in all namespaces
for namespace in "${NAMESPACES[@]}"; do
    generate_samples_in_namespace "${namespace}"
done

echo "[generate-otel-sample] 🎉 Done generating samples across all namespaces!"
echo "[generate-otel-sample] Check Grafana (http://localhost:3000) for traces, logs, and metrics."