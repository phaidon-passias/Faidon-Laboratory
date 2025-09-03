# Solution

## Files provided (an explanation of the scripts and their functionality is at the bottom)

`makefile`: A makefile to help with the creation/deletion of the cluster, deployment of app, deploying of monitoring (opentelemetry), gitops(prefered tool is fluxCD)

`kind-three-node.yaml`: Simple three node cluster with 2 workers and one controlplane

`setup-all.sh`: Setup all via make targets. Cluster, services, API metrics server

`hpa-demo`: HPA demo via make targets. Create load, scale to 5 replicas

`teardown-all.sh`: Teardown all infrastructure/apps via make targets. Gooooooodbye 

`debug-metrics-simple.sh`: Create a debug pod in the monitoring namespace and query app metrics using make targets. Cross namespace communication and accessibility while network policies allow namespace isolation


## Part 1 – Kubernetes and Application setup:

### Kubernetes using Kind 

- Provided kind-three-node (Used Kind)
- Started my Makefile and run the application after some errors with the 5000 port on mac (Did you know that airplay receiver uses the same port as the registry? neither did i.)

### Application base manifests and refining

**Core Infrastructure:**
- [x] **Namespace & Isolation** – Deploy in dedicated namespace with meaningful labels and NetworkPolicy for traffic isolation
- [x] **Node Placement** – Use nodeSelector/affinity to ensure pods run only on worker nodes
- [x] **Workload Controller** – Choose appropriate controller (Deployment recommended for stateless apps) and justify selection
- [x] **Service Exposure** – Create Service resource and justify exposure method (ClusterIP/NodePort/LoadBalancer)

**Application Configuration:**
- [x] **Secrets Management** – Source `GREETING` from Kubernetes Secret (use stringData for simplicity)
- [x] **Configuration Management** – Source `READINESS_DELAY_SEC` and `FAIL_RATE` from ConfigMap
- [x] **Environment Variables** – Configure any additional deployment-specific variables as needed

**Operational Excellence:**
- [x] **Health Probes** – Configure readiness and liveness probes (account for 10-second startup delay)
- [x] **Resource Management** – Set CPU/memory requests and limits with clear justification (consider latency vs. cost trade-offs)
- [x] **Security Configuration** – Implement SecurityContext with non-root user, read-only root filesystem, and minimal capabilities
- [x] **Scaling Strategy** – Implement HorizontalPodAutoscaler using CPU/memory metrics (document metrics-server requirements)
- [x] **Availability Protection** – Configure PodDisruptionBudget to ensure service availability during updates

**Advanced Considerations:**
- [x] **Resource Quotas** – Consider namespace-level resource quotas for multi-tenancy
- [x] **Monitoring Integration** – Ensure `/metrics` endpoint is accessible for monitoring setup

### Implementation Details

**What I've Implemented:**
- ✅ **Secret and ConfigMap**: Created as stated in assignment.md for `GREETING`, `READINESS_DELAY_SEC`, and `FAIL_RATE`
- ✅ **PodDisruptionBudget**: Set to 50% to prevent all pods from being terminated during rollouts (critical for stateless apps)
- ✅ **Node Affinity**: Used affinity rules to ensure pods only run on worker nodes (avoiding controlplane)
- ✅ **Network Policies**: Implemented default-deny with allow rules for same namespace and monitoring namespace
- ✅ **RBAC**: Added service account permissions to read secrets and configmaps
- ✅ **Deployment Strategy**: Set replicas to 2 with PDB ensuring 50% availability
- ✅ **HPA Configuration**: Configured for 2-5 pods with CPU-based scaling
- ✅ **Security**: Added non-root user, read-only filesystem, and minimal capabilities
- ✅ **Resource Management**: Set CPU/memory requests and limits
- ✅ **Health Probes**: Configured readiness/liveness with proper startup delays
- ✅ **Namespace Quotas**: Added resource quotas and limit ranges
- ✅ **Labels**: Applied consistent labeling across all resources

**Design Decisions & Justifications:**
- **Stateless App**: Chose Deployment over StatefulSet since the app has no persistent state
- **Service Type**: Used ClusterIP with port-forward for development simplicity
- **Replica Count**: Started with 2 replicas for high availability, scaling to 5 max
- **Security Context**: Non-root execution with minimal privileges for production readiness
- **Network Policy**: Default-deny approach with explicit allow rules for security

**Production Considerations:**
- For production secrets, I'd recommend External Secrets Operator (ESO) with AWS Secret Manager for encrypted storage
- ConfigMaps are appropriate for non-sensitive configuration data
- Consider custom metrics for HPA in larger infrastructures
- Added DNS egress rules (UDP 53) for proper name resolution

### Part 1 Acceptance Criteria

- [x] Application accessible via port-forward to service on port 8000
- [x] All health endpoints (`/healthz`, `/readyz`, `/work`, `/metrics`) respond correctly
- [x] Resource requests/limits configured and justified in documentation
- [x] Security context configured (non-root execution, minimal privileges)
- [x] NetworkPolicy restricts traffic appropriately within namespace
- [x] PodDisruptionBudget configured for high availability during updates
- [x] SOLUTION.md explains **why** you chose specific primitives and overall design decisions
- [x] Application successfully demonstrates configuration via Secret and ConfigMap


### Fixing a bug with the application - metrics related issue

There was a logical issue with when reporting latency, previously it only recorded latency for failed requests.
I added some code to help with reporting also successful requests. Now all requests contribute to latency metrics. If we were to scale based on latency metrics then we would face the issue that we would have incoherent data.

If the problem statement behind the decision of reporting only the failed requests would be monitoring i'd suggest filter or drop a percentage of the successful requests in your OTEL Collector. 
I see a problem if I'd set an SLA based on percentiles on this metric. Also questions like "how much Load i can handle before the service is degrades are not answered.

I'd revert if its a dev only application and i don't care about further analysis or if i have a storage issue (from our last interview Robert noted that the biggest "cost-issue" kaiko is facing is storage. I'd have to do an analysis on whether this service is critical enough)(on the other hand prometheus is very efficient in storage, i wouldn't consider it a problem)

Theoretically it would skew our metrics because 
`Current broken behavior`:
Failed requests: Record latency ✅
Successful requests: Don't record latency ❌
Result: Our Prometheus histogram only would contain data from failed requests, which means:
Average latency is artificially high (only failures, which might be slower)
Percentiles are wrong (P50, P95, P99 based on incomplete data)
HPA decisions could be wrong if you're scaling on latency metrics
Monitoring dashboards show misleading performance data

## PRODUCTION ENHANCEMENTS (TODO for later)

### Operational Excellence
- [ ] **Resource Optimization**: Increase CPU/memory requests/limits (current: 50m/64Mi → 100m/128Mi)
- [ ] **HPA Tuning**: Lower CPU target from 70% to 60%, increase min replicas from 2 to 3
- [ ] **Pod Disruption Budget**: Change from percentage to absolute numbers (minAvailable: 2)
- [ ] **Liveness Probe Tuning**: Increase timeouts (initialDelay: 30s, period: 30s, timeout: 5s)

### Monitoring & Observability
- [ ] **Prometheus Integration**: Add scrape annotations to Service
- [ ] **ServiceMonitor**: Create ServiceMonitor resource if using Prometheus Operator

### Configuration Management
- [ ] **Environment-Specific Configs**: Use Helm/Kustomize for prod vs dev settings
- [ ] **External Secrets**: Replace plain Kubernetes secrets with external-secrets-operator

### Quick Wins (Implement First)
1. Pod Security Standards (namespace labels)
2. Resource limits increase (CPU/memory)
3. HPA tuning (lower CPU target, higher min replicas)
4. Prometheus annotations on Service
5. Liveness probe tuning (higher timeouts)

## Additional Improvements I'd do

- [ ] Implement Kustomize and fluxcd and maybe helm charts
- [ ] Implement grafana prometheus  
- [ ] Pull metrics in prometheus and use otel collector

## Scripts and Automation

### Core Setup and Teardown Scripts

**`setup-all.sh`** - Complete environment setup
- Creates Kind cluster with local registry
- Installs metrics-server for HPA functionality
- Builds and pushes app Docker image to localhost:5000
- Applies all Kubernetes manifests (app + monitoring namespaces)
- Waits for application rollout completion
- Verifies all resources are running

**`teardown-all.sh`** - Complete environment cleanup
- Cleans up all application resources using Makefile targets
- Stops any lingering port-forward connections
- Deletes the entire Kind cluster
- Stops local Docker registry

### HPA Testing and Monitoring Scripts

**`hpa-demo.sh`** - HPA load testing and observation
- **`./hpa-demo.sh run`** - Generates load and captures 60s monitoring snapshots
- **`./hpa-demo.sh watch`** - Live monitoring of HPA scaling events
- **`./hpa-demo.sh stop`** - Stops any running port-forward connections
- Configurable concurrency (default: 200) and duration (default: 120s)
- Uses `hey` tool if available, falls back to curl for load generation

### Debug and Troubleshooting Scripts

**`debug-metrics-simple.sh`** - Cross-namespace metrics testing
- Creates debug pod in monitoring namespace using `nicolaka/netshoot` image
- Tests connectivity from monitoring → app namespace
- Validates metrics endpoint accessibility (`/metrics`)
- Shows metrics summary and HTTP request statistics
- **Smart pod reuse**: Reuses existing debug pod if available
- **Network policy validation**: Demonstrates proper cross-namespace communication

### Makefile Targets

**Cluster Management:**
- `make start-cluster` - Creates cluster, registry, metrics-server, and monitoring namespace
- `make stop-cluster` - Stops registry and deletes cluster
- `make create-monitoring` - Creates monitoring namespace with proper RBAC and network policies
- `make cleanup-monitoring` - Removes monitoring namespace and resources

**Application Management:**
- `make build-and-push-services` - Builds and pushes app Docker image
- `make cleanup-app` - Removes app namespace and resources
- `make cleanup-all` - Removes both app and monitoring resources

**Debug and Testing:**
- `make debug-container` - Debug pod in default namespace
- `make debug-app` - Debug pod in app namespace
- `make debug-monitoring` - Debug pod in monitoring namespace
- `make hpa-load` - Port-forward and generate load for HPA testing
- `make hpa-watch` - Watch HPA scaling events in real-time

**HPA Testing:**
- `make hpa-load` - Generates configurable load (HPA_CONCURRENCY, HPA_DURATION)
- `make hpa-watch` - Real-time HPA monitoring
- `make hpa-stop` - Cleanup port-forward connections

### Script Features and Capabilities

**Cross-Namespace Testing:**
- Monitoring namespace can access app metrics endpoint
- Proper network policy enforcement
- DNS resolution working across namespaces
- Service discovery functioning correctly

**Load Testing:**
- Configurable concurrency and duration
- Automatic port-forward management
- Graceful cleanup on script exit
- Fallback load generation methods

**Debugging:**
- Interactive debug pod access
- Network connectivity testing
- Metrics endpoint validation
- Service health checks

**Resource Management:**
- Automatic cleanup of temporary resources
- Pod reuse for efficiency
- Proper error handling and status reporting
- Resource quota and limit enforcement

### Usage Examples

```bash
# Complete setup
./setup-all.sh

# Test metrics endpoint from monitoring namespace
./debug-metrics-simple.sh

# Generate load and test HPA
HPA_CONCURRENCY=300 HPA_DURATION=180 ./hpa-demo.sh run

# Watch HPA scaling
./hpa-demo.sh watch

# Cleanup everything
./teardown-all.sh

# Or use Makefile targets
make start-cluster
make debug-monitoring
make hpa-load
make cleanup-all
```

### Script Dependencies

- **kubectl** - Kubernetes cluster management
- **kind** - Local cluster creation
- **docker** - Image building and registry
- **hey** (optional) - Load testing tool
- **curl** - HTTP requests and fallback load generation
- **make** - Build automation and target management

### Network Architecture

The scripts demonstrate a proper multi-namespace setup:
- **App Namespace**: Application pods, services, and network policies
- **Monitoring Namespace**: Debug tools, monitoring resources, and cross-namespace access
- **Network Policies**: Default-deny with explicit allow rules for monitoring → app communication
- **Service Discovery**: DNS resolution working across namespace boundaries

## GitOps

### Structure of IaC

✅ Decisions:
Thread 1: Single cluster, 3 namespaces ✅
Thread 2: Hybrid approach (Kustomize + Helm) ✅
Thread 3: Monorepo with environment directories ✅
Thread 4: Progressive environment configurations ✅
Thread 5: FluxCD in separate namespace ✅

#### Directory Organization and Design Decisions

```
flux-cd/                                    # Root directory for all GitOps-managed resources
│                                           # Managed entirely by FluxCD controllers
│
├── foundation/                             # Cluster-wide, one-time setup configurations
│   ├── cluster-rbac/                      # Cluster-wide RBAC, service accounts, cluster roles
│   ├── cluster-storage/                    # Storage classes, persistent volumes, CSI drivers
│   └── cluster-networking/                 # Cluster-wide networking (ingress controllers, CNI configs)
│
├── environments/                           # Environment-specific namespace definitions
│   ├── dev/                               # Development environment namespace + basic configs
│   ├── staging/                           # Staging environment namespace + basic configs
│   ├── production/                        # Production environment namespace + basic configs
│   └── monitoring/                        # Monitoring namespace + basic configs
│
├── applications/                           # Application definitions and configurations
│   ├── base-app-config/                   # Base Kustomize configuration for the application
│   │                                      # Contains: deployment, service, configmap, app-specific netpols
│   ├── mock-cluster-aka-namespaces/       # Environment-specific Kustomize overlays
│   │   ├── dev/                           # Dev environment patches (replicas=1, low resources, debug enabled)
│   │   ├── staging/                       # Staging environment patches (replicas=2, medium resources)
│   │   └── production/                    # Production environment patches (replicas=3+, high resources)
│   └── values/                            # Environment-specific Helm values (moved from helm-charts/)
│       ├── dev/                           # Dev environment Helm values
│       ├── staging/                       # Staging environment Helm values
│       └── production/                    # Production environment Helm values
│
├── infrastructure/                         # Shared infrastructure components across environments
│   ├── monitoring-stack/                  # Prometheus, Grafana, alerting (shared across environments)
│   ├── cross-namespace-netpols/           # Cross-namespace network policies (platform team managed)
│   └── ingress-controllers/               # Ingress controllers, load balancers, service mesh
│
└── bootstrap/                              # FluxCD system configuration and bootstrap
    ├── flux-system/                       # FluxCD system namespace (created by bootstrap)
    # FluxCD installation and bootstrap is now handled directly in setup-all.sh

helm-charts/                                # Helm chart definitions (templating engine)
└── app/                                   # Application Helm chart
    ├── Chart.yaml                         # Chart metadata with Go templating capabilities
    ├── default-values.yaml                # Base values for the application
    └── templates/                         # Chart templates (to be created)
```

#### Key Design Decisions and Rationale

##### 1. Separation of Concerns
- **`foundation/`**: Cluster-wide configurations managed by platform engineers
- **`environments/`**: Namespace definitions and basic environment setup
- **`applications/`**: Application-specific configurations managed by application teams
- **`infrastructure/`**: Shared components managed by platform engineers
- **`bootstrap/`**: FluxCD system itself

##### 2. Application values Directory Relocation Decision 
**Original Structure**: `helm-charts/app/k8s/{dev,staging,production}/`
**New Structure**: `flux-cd/applications/values/{dev,staging,production}/`

**Rationale for Moving Values**:
- **Application Cohesion**: Environment values are now co-located with application configurations
- **FluxCD Proximity**: Values are closer to where FluxCD manages the application lifecycle
- **Developer Experience**: Application teams work in one place for all app-related configs
- **Logical Grouping**: Values are with the Kustomize overlays they relate to
- **Clear Separation**: Helm charts focus on templating, values focus on environment configuration

##### 3. Network Policy Organization
- **App-specific netpols**: Located in `applications/base-app-config/` (managed by app teams) *tricky* maybe there can be a middleware in the creation of apps that creates PRs
- **Cross-namespace netpols**: Located in `infrastructure/cross-namespace-netpols/` (managed by platform teams) *less tricky* we can create a set number of ports for our apps. Process.
- **Cluster-wide netpols**: Located in `foundation/cluster-networking/` (managed by platform teams). This is used for general cluster-wide netpols we need

**Rationale**: Platform engineers handle cross-cutting networking concerns, application teams focus on app-specific policies with a backend provided by Platform team.

##### 4. Environment Configuration Strategy
- **Development**: 1 replica, low resources, debug enabled, basic monitoring
- **Staging**: 2 replicas, medium resources, debug disabled, full monitoring
- **Production**: 3+ replicas, high resources, debug disabled, full monitoring + alerting

##### 5. FluxCD Management Scope
FluxCD manages everything in the `flux-cd/` directory, providing:
- **GitOps workflow**: Commit → Auto-deploy
- **Environment isolation**: Separate namespaces with different configurations
- **Infrastructure as Code**: All configurations version controlled
- **Progressive rollout**: Dev → Staging → Production deployment pipeline

This structure enables clear ownership, minimal duplication, and maximum reusability while maintaining proper separation between platform and application concerns.




TODO: Screenshots for everything.
TODO: ADD documentation on how to use flux with their setup....