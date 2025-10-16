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
    
    # Trigger all new business endpoints to generate comprehensive telemetry
    echo "[generate-otel-sample] Triggering comprehensive business workflows in ${namespace}..."
    kubectl -n "${namespace}" run "business-workflow-${namespace}-$$" \
      --image=curlimages/curl:latest \
      --restart=Never \
      --command -- sh -c \
      "echo '=== API Gateway Business Endpoints ===' && \
       echo '1. Creating user via API Gateway...' && \
       curl -X POST http://api-gateway-${namespace}.${namespace}.svc.cluster.local:8080/api/users \
         -H 'Content-Type: application/json' \
         -d '{\"name\":\"Test User ${namespace}\",\"email\":\"test-${namespace}@example.com\",\"role\":\"user\"}' \
         -s -w 'Status: %{http_code}\n' || echo 'User creation failed' && \
       echo '2. Getting user profile...' && \
       curl -X GET http://api-gateway-${namespace}.${namespace}.svc.cluster.local:8080/api/users/123 \
         -s -w 'Status: %{http_code}\n' || echo 'User lookup failed' && \
       echo '3. Getting notifications...' && \
       curl -X GET http://api-gateway-${namespace}.${namespace}.svc.cluster.local:8080/api/notifications \
         -s -w 'Status: %{http_code}\n' || echo 'Notifications fetch failed' && \
       echo '4. Processing business workflow...' && \
       curl -X POST http://api-gateway-${namespace}.${namespace}.svc.cluster.local:8080/api/process \
         -H 'Content-Type: application/json' \
         -d '{\"workflow_id\":\"test-workflow-${namespace}\",\"priority\":\"high\",\"data\":{\"amount\":1000}}' \
         -s -w 'Status: %{http_code}\n' || echo 'Workflow processing failed' && \
       echo '=== Direct Service Endpoints ===' && \
       echo '5. User Service - Create user...' && \
       curl -X POST http://user-service-${namespace}.${namespace}.svc.cluster.local:8000/users \
         -H 'Content-Type: application/json' \
         -d '{\"name\":\"Direct User ${namespace}\",\"email\":\"direct-${namespace}@example.com\"}' \
         -s -w 'Status: %{http_code}\n' || echo 'Direct user creation failed' && \
       echo '6. User Service - Get user profile...' && \
       curl -X GET http://user-service-${namespace}.${namespace}.svc.cluster.local:8000/users/456/profile \
         -s -w 'Status: %{http_code}\n' || echo 'User profile fetch failed' && \
       echo '7. Notification Service - Get notifications...' && \
       curl -X GET http://notification-service-${namespace}.${namespace}.svc.cluster.local:8000/notifications \
         -s -w 'Status: %{http_code}\n' || echo 'Direct notifications fetch failed' && \
       echo '8. Notification Service - Get status...' && \
       curl -X GET http://notification-service-${namespace}.${namespace}.svc.cluster.local:8000/notifications/status \
         -s -w 'Status: %{http_code}\n' || echo 'Notification status failed' && \
       echo '9. Health checks...' && \
       curl -s http://user-service-${namespace}.${namespace}.svc.cluster.local:8000/health -w 'User Service: %{http_code}\n' || echo 'User service health failed' && \
       curl -s http://notification-service-${namespace}.${namespace}.svc.cluster.local:8000/health -w 'Notification Service: %{http_code}\n' || echo 'Notification service health failed' && \
       echo '=== Business Workflow Complete ==='; sleep 3" || echo "Failed to trigger business workflows in ${namespace}"
    
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
    kubectl -n "${namespace}" delete pod "business-workflow-${namespace}-$$" --ignore-not-found 2>/dev/null || true
    kubectl -n "${namespace}" delete pod "log-generator-${namespace}-$$" --ignore-not-found 2>/dev/null || true
    
    echo "[generate-otel-sample] ✓ Completed samples for ${namespace}"
    echo ""
}

# Generate samples in all namespaces
for namespace in "${NAMESPACES[@]}"; do
    generate_samples_in_namespace "${namespace}"
done

echo "[generate-otel-sample] 🎉 Done generating comprehensive business workflow samples across all namespaces!"
echo "[generate-otel-sample] Generated telemetry for:"
echo "  • API Gateway business endpoints (user CRUD, notifications, workflows)"
echo "  • Direct service endpoints (user profiles, notification status)"
echo "  • Health checks and synthetic traces"
echo "  • Sample logs and metrics"
echo ""
echo "[generate-otel-sample] Check Grafana (http://localhost:3000) for:"
echo "  • SLI Overview dashboard - success rates, latency, error budgets"
echo "  • Service Health dashboard - CPU, memory, restarts"
echo "  • Business KPIs - request rates and endpoint usage"
echo ""
echo "[generate-otel-sample] Use: kubectl port-forward -n monitoring svc/lgtm-stack-grafana 3000:80"