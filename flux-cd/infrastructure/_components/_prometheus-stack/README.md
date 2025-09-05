# Monitoring Stack

This directory contains the GitOps configuration for deploying the kube-prometheus-stack using Flux CD.

## Components

The monitoring stack includes:

- **Prometheus**: Metrics collection and storage
- **Grafana**: Metrics visualization and dashboards
- **Alertmanager**: Alert routing and notification
- **Node Exporter**: Node-level metrics collection
- **Kube State Metrics**: Kubernetes cluster metrics

## Files

- `namespace.yaml`: Creates the `monitoring` namespace
- `helmrepository.yaml`: References the Prometheus Community Helm charts repository
- `configmap.yaml`: Contains the Helm chart values configuration
- `helmrelease.yaml`: Deploys the kube-prometheus-stack using Helm
- `kustomization.yaml`: Kustomize configuration to include all resources

## Configuration

### Storage
- Prometheus: 10Gi persistent storage
- Grafana: 5Gi persistent storage  
- Alertmanager: 5Gi persistent storage

### Resources
- Prometheus: 256Mi-1Gi memory, 100m-500m CPU
- Grafana: 128Mi-512Mi memory, 100m-200m CPU
- Alertmanager: 128Mi-256Mi memory, 100m-200m CPU

### Access
- Grafana admin password: `admin`
- Services are exposed as ClusterIP (internal access only)
- Use port-forwarding or ingress to access externally

## Deployment

The stack is deployed automatically by Flux CD when changes are pushed to the repository. The deployment order is:

1. Namespace creation
2. ConfigMap creation
3. HelmRepository creation
4. HelmRelease deployment

## Monitoring

Once deployed, you can:

1. Port-forward to Grafana: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`
2. Access Grafana at `http://localhost:3000` (admin/admin)
3. Port-forward to Prometheus: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090`
4. Access Prometheus at `http://localhost:9090`

## Customization

To modify the configuration:

1. Edit the `configmap.yaml` file
2. Commit and push the changes
3. Flux will automatically redeploy the stack with the new configuration
