# OpenTelemetry + LGTM Stack Deployment Guide

## Overview

This guide documents the complete observability stack deployment using Flux CD, OpenTelemetry, and the LGTM stack (Loki, Grafana, Tempo, Mimir).

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Applications  │    │  Grafana Alloy   │    │   LGTM Stack    │
│                 │    │   (Collector)    │    │                 │
│ ┌─────────────┐ │    │                  │    │ ┌─────────────┐ │
│ │ Go App      │─┼────┼─► OTLP Receiver  │    │ │   Mimir     │ │
│ │ Python App  │ │    │                  │    │ │ (Metrics)   │ │
│ └─────────────┘ │    │ ┌──────────────┐ │    │ └─────────────┘ │
│                 │    │ │ k8s-monitoring│ │    │                 │
│                 │    │ │ (Collector)   │─┼────┼─► Metrics      │
│                 │    │ └──────────────┘ │    │                 │
│                 │    │                  │    │ ┌─────────────┐ │
│                 │    │ ┌──────────────┐ │    │ │    Loki     │ │
│                 │    │ │ OTLP Export  │─┼────┼─► (Logs)     │ │
│                 │    │ │ (Logs)       │ │    │ └─────────────┘ │
│                 │    │ └──────────────┘ │    │                 │
│                 │    │                  │    │ ┌─────────────┐ │
│                 │    │ ┌──────────────┐ │    │ │    Tempo    │ │
│                 │    │ │ OTLP Export  │─┼────┼─► (Traces)   │ │
│                 │    │ │ (Traces)     │ │    │ └─────────────┘ │
│                 │    │ └──────────────┘ │    │                 │
└─────────────────┘    └──────────────────┘    │ ┌─────────────┐ │
                                               │ │   Grafana   │ │
                                               │ │(Visualization)│
                                               │ └─────────────┘ │
                                               └─────────────────┘
```

## Components

### 1. LGTM Stack
- **Loki**: Log aggregation system
- **Grafana**: Visualization and dashboards
- **Tempo**: Distributed tracing backend
- **Mimir**: Prometheus-compatible metrics storage

### 2. Grafana Alloy
- Telemetry collector that replaces Grafana Agent
- Receives OTLP data from applications
- Forwards data to LGTM stack components

### 3. k8s-monitoring
- Collects Kubernetes cluster metrics
- Forwards metrics to Mimir

### 4. Applications
- Go and Python applications instrumented with OpenTelemetry
- Send telemetry data via OTLP to Alloy collector

## Quick Start

### Prerequisites
- Docker
- Kind (Kubernetes in Docker)
- kubectl
- Flux CLI
- Git

### Deploy Everything
```bash
# Make the script executable
chmod +x scripts/deploy-observability-stack.sh

# Deploy the complete stack
./scripts/deploy-observability-stack.sh deploy

# Check status
./scripts/deploy-observability-stack.sh status

# Test the pipeline
./scripts/deploy-observability-stack.sh test

# Clean up when done
./scripts/deploy-observability-stack.sh cleanup
```

## Manual Deployment Steps

### 1. Create Kind Cluster
```bash
kind create cluster --config scripts/kind-three-node.yaml
```

### 2. Setup Local Registry
```bash
docker run -d --restart=always -p 5000:5000 --name kind-registry registry:2
docker network connect kind kind-registry
```

### 3. Build and Push Images
```bash
# Build Go app
cd app-go
docker build -t localhost:5000/demo-app-go:latest .
docker push localhost:5000/demo-app-go:latest
cd ..

# Build Python app
cd app-python
docker build -t localhost:5000/demo-app-python:latest .
docker push localhost:5000/demo-app-python:latest
cd ..
```

### 4. Install Flux CD
```bash
flux install
```

### 5. Bootstrap Flux
```bash
flux bootstrap git \
  --url=$(git remote get-url origin) \
  --branch=main \
  --path=./flux-cd/bootstrap
```

### 6. Wait for Deployment
```bash
flux get kustomizations
kubectl get pods -n monitoring
```

## Accessing Services

### Port Forwarding
```bash
# Grafana (admin/admin)
kubectl port-forward -n monitoring svc/lgtm-stack-grafana 3000:80

# Go App (dev)
kubectl port-forward -n dev svc/demo-app-go-dev 8080:80

# Python App (dev)
kubectl port-forward -n dev svc/demo-app-python-dev 8081:80
```

### URLs
- **Grafana**: http://localhost:3000
- **Go App**: http://localhost:8080
- **Python App**: http://localhost:8081

## Configuration Files

### Key Configuration Files

1. **LGTM Stack Configuration**
   - `flux-cd/infrastructure/_components/_lgtm-stack/configmap.yaml`
   - Defines Grafana, Loki, Tempo, and Mimir settings

2. **Alloy Configuration**
   - `flux-cd/infrastructure/_components/_alloy/configmap.yaml`
   - Configures OTLP receivers and exporters

3. **k8s-monitoring Configuration**
   - `flux-cd/infrastructure/_components/_k8s-monitoring/configmap.yaml`
   - Configures cluster metrics collection

4. **Application Configuration**
   - `flux-cd/applications/_base-app-config/configmap.yaml`
   - Common application settings including OpenTelemetry endpoints

## Service Endpoints

### LGTM Stack Services
- **Mimir (Metrics)**: `lgtm-stack-mimir-nginx:80`
- **Loki (Logs)**: `lgtm-stack-loki-gateway:80`
- **Tempo (Traces)**: `lgtm-stack-tempo-distributor:9095` (gRPC)
- **Grafana**: `lgtm-stack-grafana:80`

### Alloy Collector
- **OTLP Receiver**: `grafana-alloy:4317` (gRPC), `grafana-alloy:4318` (HTTP)

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   kubectl get events --sort-by='.lastTimestamp'
   ```

2. **Alloy connection issues**
   ```bash
   kubectl logs -n monitoring grafana-alloy-<pod-id> -c alloy
   ```

3. **Application not sending telemetry**
   ```bash
   kubectl logs -n dev demo-app-go-dev-<pod-id>
   kubectl get configmap -n dev demo-app-go-dev-config -o yaml
   ```

4. **Grafana data source issues**
   - Check Grafana logs: `kubectl logs -n monitoring lgtm-stack-grafana-<pod-id>`
   - Verify service endpoints are correct

### Debugging Commands

```bash
# Check all pods
kubectl get pods --all-namespaces

# Check services
kubectl get svc -n monitoring

# Check Flux status
flux get kustomizations
flux get helmreleases -n monitoring

# Check application logs
kubectl logs -n dev demo-app-go-dev-<pod-id>
kubectl logs -n dev demo-app-python-dev-<pod-id>

# Check Alloy logs
kubectl logs -n monitoring grafana-alloy-<pod-id> -c alloy

# Check LGTM stack logs
kubectl logs -n monitoring lgtm-stack-grafana-<pod-id>
kubectl logs -n monitoring lgtm-stack-mimir-<component>-<pod-id>
```

## Testing the Pipeline

### 1. Generate Traffic
```bash
# Generate requests to create telemetry data
for i in {1..10}; do
  curl http://localhost:8080/work
  curl http://localhost:8081/work
  sleep 1
done
```

### 2. Verify Data Flow
```bash
# Check Alloy is receiving data
kubectl logs -n monitoring grafana-alloy-<pod-id> -c alloy --tail=10

# Check if data reaches Mimir
curl -s "http://localhost:3000/api/datasources/proxy/1/api/v1/query?query=up" | jq
```

### 3. View in Grafana
1. Open http://localhost:3000
2. Login with admin/admin
3. Go to Explore
4. Select Prometheus data source
5. Run query: `up{job="demo-app-go-dev"}`
6. Check Loki for logs: `{job="demo-app-go-dev"}`
7. Check Tempo for traces: Search by service name

## Customization

### Adding New Applications
1. Create new namespace configuration in `flux-cd/applications/mock-cluster-aka-namespaces/`
2. Add application deployment with OpenTelemetry instrumentation
3. Configure `ALLOY_URL` environment variable to point to Alloy collector

### Modifying Alloy Configuration
1. Edit `flux-cd/infrastructure/_components/_alloy/configmap.yaml`
2. Commit and push changes
3. Flux will automatically reconcile the changes

### Adding Custom Dashboards
1. Create dashboard JSON in Grafana
2. Add to `flux-cd/infrastructure/_components/_lgtm-stack/configmap.yaml`
3. Commit and push changes

## Monitoring and Alerting

### Built-in Monitoring
- Kubernetes cluster metrics via k8s-monitoring
- Application metrics via OpenTelemetry
- Infrastructure metrics via Alloy

### Grafana Dashboards
- Kubernetes cluster overview
- Application performance metrics
- Log analysis
- Distributed tracing

## Security Considerations

### Network Policies
- Network policies are configured to restrict traffic between namespaces
- Only necessary communication is allowed

### RBAC
- Service accounts with minimal required permissions
- Role-based access control for different components

### Secrets Management
- Grafana admin password stored in Kubernetes secrets
- Application secrets managed via Flux

## Performance Tuning

### Resource Limits
- All components have resource requests and limits
- Horizontal Pod Autoscalers configured for scaling

### Storage
- Persistent volumes for Grafana, Loki, Tempo, and Mimir
- Local-path storage class for Kind cluster

### Optimization Tips
- Adjust retention periods based on storage capacity
- Configure sampling rates for high-volume applications
- Use appropriate scrape intervals for metrics collection

## Backup and Recovery

### Data Persistence
- All critical data stored in persistent volumes
- Regular backups recommended for production use

### Configuration Backup
- All configuration stored in Git repository
- Flux CD ensures configuration consistency

## Production Considerations

### Scaling
- Mimir can be scaled horizontally for metrics storage
- Loki can be scaled for log ingestion
- Tempo can be scaled for trace processing

### High Availability
- Multiple replicas for critical components
- Pod disruption budgets configured
- Anti-affinity rules for distribution

### Monitoring
- Monitor the monitoring stack itself
- Set up alerts for component failures
- Regular health checks and maintenance

## Support and Maintenance

### Regular Tasks
- Monitor resource usage and scaling needs
- Update component versions regularly
- Review and optimize configuration
- Backup critical data

### Getting Help
- Check component documentation
- Review logs for error messages
- Use debugging commands provided
- Consult Grafana and OpenTelemetry documentation

---

## Quick Reference

### Essential Commands
```bash
# Deploy everything
./scripts/deploy-observability-stack.sh deploy

# Check status
./scripts/deploy-observability-stack.sh status

# Test pipeline
./scripts/deploy-observability-stack.sh test

# Clean up
./scripts/deploy-observability-stack.sh cleanup

# Port forward services
kubectl port-forward -n monitoring svc/lgtm-stack-grafana 3000:80
kubectl port-forward -n dev svc/demo-app-go-dev 8080:80
kubectl port-forward -n dev svc/demo-app-python-dev 8081:80
```

### Key URLs
- Grafana: http://localhost:3000 (admin/admin)
- Go App: http://localhost:8080
- Python App: http://localhost:8081

### Important Files
- Deployment script: `scripts/deploy-observability-stack.sh`
- LGTM config: `flux-cd/infrastructure/_components/_lgtm-stack/configmap.yaml`
- Alloy config: `flux-cd/infrastructure/_components/_alloy/configmap.yaml`
- App config: `flux-cd/applications/_base-app-config/configmap.yaml`
