# OpenTelemetry Setup with LGTM Stack

## Overview

This document describes the complete OpenTelemetry (OTEL) setup using Grafana Alloy as the collector and the LGTM (Loki, Grafana, Tempo, Mimir/Prometheus) stack for observability.

## Architecture

```
Applications (Go/Python) 
    ↓ OTLP (4317/4318)
Grafana Alloy (Collector)
    ↓
┌─────────────────┬─────────────────┬─────────────────┐
│   Prometheus    │      Loki       │      Tempo      │
│   (Metrics)     │     (Logs)      │    (Traces)     │
└─────────────────┴─────────────────┴─────────────────┘
    ↓
  Grafana (Visualization)
```

## Components

### 1. Applications
- **Go App**: Uses native OpenTelemetry Go SDK
- **Python App**: Uses Prometheus client (can be upgraded to OTEL)
- Both send telemetry data via OTLP to Alloy collector

### 2. Grafana Alloy (Collector)
- **OTLP Receiver**: Listens on ports 4317 (gRPC) and 4318 (HTTP)
- **Resource Detection**: Adds Kubernetes metadata
- **Transform Processor**: Maps namespace to environment
- **Exporters**: Routes data to Prometheus, Loki, and Tempo

### 3. LGTM Stack
- **Prometheus**: Metrics storage and querying
- **Loki**: Log aggregation
- **Tempo**: Distributed tracing
- **Grafana**: Visualization and dashboards

## Configuration

### Application Configuration

#### Go Application
```go
// OTLP Configuration
alloyURL = getEnvString("ALLOY_URL", "grafana-alloy.monitoring.svc.cluster.local:4318")

// Trace Exporter
traceExporter, err := otlptracehttp.New(ctx,
    otlptracehttp.WithEndpoint(alloyURL),
    otlptracehttp.WithInsecure(),
)

// Metric Exporter  
metricExporter, err := otlpmetrichttp.New(ctx,
    otlpmetrichttp.WithEndpoint(alloyURL),
    otlpmetrichttp.WithInsecure(),
)
```

#### Environment Variables
```yaml
# Base configuration
alloy_url: "grafana-alloy.monitoring.svc.cluster.local:4318"
service_name: "APP_NAME"
service_version: "1.0.0"
environment: "development"
```

### Alloy Configuration

```alloy
// OTLP Receiver
otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "0.0.0.0:4317"
  }
  http {
    endpoint = "0.0.0.0:4318"
  }
  
  output {
    metrics = [otelcol.processor.resourcedetection.basic_detection.input]
    logs    = [otelcol.processor.resourcedetection.basic_detection.input]
    traces  = [otelcol.processor.resourcedetection.basic_detection.input]
  }
}

// Resource Detection
otelcol.processor.resourcedetection "basic_detection" {
  detectors = ["env", "system"]
  
  output {
    metrics = [otelcol.processor.transform.namespace_to_env.input]
    logs    = [otelcol.processor.transform.namespace_to_env.input]
    traces  = [otelcol.processor.transform.namespace_to_env.input]
  }
}

// Transform Processor
otelcol.processor.transform "namespace_to_env" {
  error_mode = "ignore"
  
  metric_statements {
    context = "resource"
    statements = [
      "set(attributes[\"environment\"], attributes[\"k8s.namespace.name\"]) where attributes[\"k8s.namespace.name\"] != nil",
      "set(attributes[\"cluster_name\"], \"kind-cluster\") where true",
      "set(attributes[\"collector\"], \"alloy\") where true",
    ]
  }
  
  output {
    metrics = [otelcol.exporter.prometheus.prometheus.input]
    logs    = [otelcol.exporter.otlp.loki.input]
    traces  = [otelcol.exporter.otlp.tempo.input]
  }
}

// Exporters
otelcol.exporter.prometheus "prometheus" {
  forward_to = [prometheus.remote_write.prometheus.receiver]
}

otelcol.exporter.otlp "loki" {
  client {
    endpoint = "http://loki:3100"
    tls {
      insecure = true
    }
  }
}

otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "http://tempo:3200"
    tls {
      insecure = true
    }
  }
}
```

## Network Policies

### Allow OTLP to Monitoring
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-otlp-to-monitoring
  namespace: dev
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - ports:
    - port: 4317
      protocol: TCP
    - port: 4318
      protocol: TCP
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
```

## Troubleshooting

### Common Issues

1. **DNS Resolution Failure**
   - **Problem**: `dial tcp: lookup grafana-alloy on 10.96.0.10:53: no such host`
   - **Solution**: Use full FQDN: `grafana-alloy.monitoring.svc.cluster.local:4318`

2. **Network Policy Blocking**
   - **Problem**: Connection refused to monitoring namespace
   - **Solution**: Ensure `allow-otlp-to-monitoring` policy allows ports 4317/4318

3. **Alloy Not Receiving Data**
   - **Problem**: No metrics/traces in Grafana
   - **Solution**: Check Alloy logs and OTLP receiver configuration

### Debugging Commands

```bash
# Check Alloy logs
kubectl logs -n monitoring grafana-alloy-<pod-id> -c alloy

# Test DNS resolution
kubectl exec -n dev <app-pod> -- nslookup grafana-alloy.monitoring.svc.cluster.local

# Check network policies
kubectl get networkpolicies -n dev

# Test OTLP connectivity
kubectl exec -n dev <app-pod> -- curl -v http://grafana-alloy.monitoring.svc.cluster.local:4318/v1/traces

# Check service endpoints
kubectl get svc -n monitoring
kubectl get endpoints -n monitoring
```

## Testing the Setup

### 1. Generate Traffic
```bash
# Port forward to application
kubectl port-forward -n dev svc/demo-app-go-dev 8080:8080

# Generate requests
for i in {1..10}; do
  curl http://localhost:8080/work
  sleep 1
done
```

### 2. Verify in Grafana
- **Metrics**: Check Prometheus data source
- **Traces**: Check Tempo data source  
- **Logs**: Check Loki data source

### 3. Check Alloy Metrics
```bash
# Port forward to Alloy
kubectl port-forward -n monitoring svc/grafana-alloy 12345:12345

# Check Alloy metrics
curl http://localhost:12345/metrics
```

## Next Steps

1. **Upgrade Python App**: Replace Prometheus client with OpenTelemetry Python SDK
2. **Add Logging**: Implement structured logging with OTEL
3. **Custom Dashboards**: Create Grafana dashboards for application metrics
4. **Alerting**: Set up Alertmanager rules for application health
5. **Distributed Tracing**: Add trace context propagation between services

## Files Modified

- `flux-cd/applications/_base-app-config/configmap.yaml`: Fixed ALLOY_URL to use FQDN
- `flux-cd/infrastructure/_components/_alloy/configmap.yaml`: Alloy configuration
- `flux-cd/infrastructure/_components/_k8s-monitoring/configmap.yaml`: LGTM stack configuration
- `app-go/main.go`: OpenTelemetry Go implementation
- `app-python/server.py`: Prometheus client (to be upgraded to OTEL)
