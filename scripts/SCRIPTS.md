# Scripts Documentation

This directory contains all automation scripts for the Kaiko Assignment Kubernetes and GitOps setup.

## 📋 Table of Contents

- [📊 Script Overview](#-script-overview)
- [🏗️ Core Setup and Teardown Scripts](#️-core-setup-and-teardown-scripts)
- [🧪 Testing and Demo Scripts](#-testing-and-demo-scripts)
- [🔍 Monitoring and Debug Scripts](#-monitoring-and-debug-scripts)
- [⚙️ Makefile Integration](#️-makefile-integration)
- [🛠️ Script Development Guidelines](#️-script-development-guidelines)

**📚 Related Documentation:**
- **[../README.md](../README.md)** - Technical implementation details and assignment completion status
- **[../how-to-run.MD](../how-to-run.MD)** - Step-by-step execution instructions and user guide
- **[../design-decisions.md](../design-decisions.md)** - Architectural decisions and trade-offs analysis

## Script Overview

| Script | Purpose | Usage |
|--------|---------|-------|
| `setup-all.sh` | Complete environment setup with Flux CD GitOps | `./scripts/setup-all.sh` |
| `teardown-all.sh` | Complete environment cleanup with Flux CD | `./scripts/teardown-all.sh` |
| `hpa-demo.sh` | HPA load testing with aggressive patterns | `./scripts/hpa-demo.sh [run|aggressive|burst|watch]` |
| `debug-metrics-simple.sh` | Cross-namespace metrics testing | `./scripts/debug-metrics-simple.sh` |
| `check-flux-ready.sh` | Verify Flux CD readiness and sync status | `./scripts/check-flux-ready.sh` |

## Core Setup and Teardown Scripts

### `setup-all.sh` - Complete Environment Setup

**Purpose**: Complete environment setup with Flux CD GitOps automation.

**What it does**:
- Creates Kind cluster with local registry
- Installs metrics-server for HPA functionality
- Installs Flux CD components directly in the cluster
- **Validates kustomizations** with kubeconform (step 4/7)
- **Bootstraps Flux CD** with your Git repository
- Builds and pushes app Docker image to localhost:5000
- **Deploys everything via Flux GitOps**
- Waits for Flux to be ready and synced
- Verifies all resources are running

**Usage**:
```bash
./scripts/setup-all.sh
```

**Dependencies**:
- `kind` - Local cluster creation
- `docker` - Image building and registry
- `flux` - Flux CD CLI for GitOps management
- `kubectl` - Kubernetes cluster management
- `kustomize` - Kustomize build and validation
- `kubeconform` - Kubernetes schema validation
- `git` - Version control

### `teardown-all.sh` - Complete Environment Cleanup

**Purpose**: Complete environment cleanup with Flux CD awareness.

**What it does**:
- Suspends Flux reconciliation
- Cleans up application resources and Flux files
- Commits cleanup to Git and pushes to main
- Stops any lingering port-forward connections
- Deletes the entire Kind cluster
- Stops local Docker registry

**Usage**:
```bash
./scripts/teardown-all.sh
```

**Dependencies**:
- `flux` - Flux CD CLI for GitOps management
- `kubectl` - Kubernetes cluster management
- `kind` - Local cluster management
- `docker` - Registry management
- `git` - Version control

## HPA Testing and Monitoring Scripts

### `hpa-demo.sh` - Aggressive HPA Load Testing with Uneven Distribution

**Purpose**: Comprehensive HPA testing with aggressive load patterns, burst spikes, and uneven distribution to stress test auto-scaling.

**Commands**:
- **`./scripts/hpa-demo.sh run`** - Standard load test (200 concurrent, 60s)
- **`./scripts/hpa-demo.sh aggressive`** - High-intensity load with uneven distribution (500+ concurrent, 90s)
- **`./scripts/hpa-demo.sh burst`** - Burst pattern with load spikes and valleys (20-600 concurrent, 120s)
- **`./scripts/hpa-demo.sh watch`** - Live monitoring of HPA scaling events

**Load Patterns**:

#### **Standard Pattern (`run`)**
- **Concurrency**: 200
- **Duration**: 60s
- **Pattern**: Steady, consistent load

#### **Aggressive Pattern (`aggressive`)**
- **Concurrency**: 500+ (2.5x more aggressive)
- **Duration**: 90s
- **Pattern**: **3-phase uneven distribution**:
  - **Phase 1**: Ramp up (0-30s) - 167 concurrent
  - **Phase 2**: Peak load (30-60s) - 500 concurrent
  - **Phase 3**: Burst spikes (60-90s) - 3x 500 concurrent for 10s each

#### **Burst Pattern (`burst`)**
- **Concurrency**: Varies dramatically (20-600)
- **Duration**: 120s
- **Pattern**: **7-phase extreme uneven distribution**:
  - **Phase 1**: Low load (0-20s) - 50 concurrent
  - **Phase 2**: First spike (20-30s) - 300 concurrent
  - **Phase 3**: Low load (30-50s) - 30 concurrent
  - **Phase 4**: Big spike (50-70s) - 600 concurrent
  - **Phase 5**: Low load (70-90s) - 40 concurrent
  - **Phase 6**: Sustained high (90-110s) - 400 concurrent
  - **Phase 7**: Final low (110-120s) - 20 concurrent

**Features**:
- **Real-world traffic patterns** with dramatic spikes and valleys
- **Enhanced monitoring** with timestamps and detailed status
- **Smart load distribution** that simulates actual user behavior
- **Comprehensive scaling events** for dramatic HPA demonstrations
- Uses `hey` tool if available, falls back to curl for load generation
- **Automatic cleanup** of port-forward connections

**Usage Examples**:
```bash
# Standard HPA test
./scripts/hpa-demo.sh run

# Aggressive load test (500+ concurrent)
./scripts/hpa-demo.sh aggressive

# Burst pattern test (extreme uneven distribution)
./scripts/hpa-demo.sh burst

# Watch scaling events live
./scripts/hpa-demo.sh watch

# Custom aggressive test
HPA_CONCURRENCY=600 HPA_DURATION=120 ./scripts/hpa-demo.sh aggressive

# Custom burst test
HPA_DURATION=180 ./scripts/hpa-demo.sh burst
```

**Makefile Integration**:
```bash
# Standard test
make hpa-demo

# Aggressive test (500+ concurrent)
make hpa-demo-aggressive

# Burst pattern test
make hpa-demo-burst

# Watch HPA scaling
make hpa-watch
```

**Dependencies**:
- `hey` (optional) - Load testing tool for advanced patterns
- `curl` - HTTP requests and fallback load generation
- `kubectl` - Kubernetes cluster management

**Expected Scaling Behavior**:
- **Scale up**: From 2 pods to 5 pods during load spikes
- **Scale down**: Back to 2 pods during low periods
- **Uneven distribution**: Real-world traffic patterns with dramatic variations
- **Visual impact**: Clear scaling events perfect for screenshots and demonstrations

**Enhanced Monitoring Features**:
- **Real-time status updates** with timestamps
- **Comprehensive pod information** including node placement
- **HPA metrics** showing current/target/desired replicas
- **Deployment status** with rollout information
- **Automatic cleanup** of port-forward connections
- **Smart error handling** with graceful fallbacks

## Kustomize Validation Scripts

### Kustomize Validation Commands

**Purpose**: Validate kustomizations and ensure configuration correctness before deployment.

**Available Commands**:
```bash
# Complete kustomize validation (structure + build + schema)
make kustomize-check

# Individual validation steps
make kustomize-build          # Build all kustomizations
make kustomize-validate       # Schema validation with kubeconform
make kustomize-lint           # Linting with kubeconform
make kustomize-structure      # Analyze kustomization structure
```

**What they do**:
- **`kustomize-check`**: Complete validation including structure analysis and build validation
- **`kustomize-build`**: Builds all kustomizations (infrastructure, applications, bootstrap)
- **`kustomize-validate`**: Validates generated resources against Kubernetes schemas using kubeconform
- **`kustomize-lint`**: Lints kustomizations for best practices and schema compliance
- **`kustomize-structure`**: Analyzes kustomization hierarchy and resource references

**Integration**:
- **Setup Process**: Validation runs automatically during `make setup-all` (step 4/7)
- **CI/CD Ready**: Commands can be integrated into CI/CD pipelines
- **Developer Workflow**: Immediate feedback on configuration errors

**Dependencies**:
- `kustomize` - Kustomize build and validation
- `kubeconform` - Kubernetes schema validation

## Debug and Troubleshooting Scripts

### `debug-metrics-simple.sh` - Cross-Namespace Metrics Testing

**Purpose**: Test metrics endpoint accessibility across namespaces with network policy validation.

**What it does**:
- Creates debug pod in monitoring namespace using `nicolaka/netshoot` image
- Tests connectivity from monitoring → app namespace
- Validates metrics endpoint accessibility (`/metrics`)
- Shows metrics summary and HTTP request statistics
- **Smart pod reuse**: Reuses existing debug pod if available
- **Network policy validation**: Demonstrates proper cross-namespace communication

**Usage**:
```bash
./scripts/debug-metrics-simple.sh
```

**Features**:
- Automatic pod creation and cleanup
- Cross-namespace connectivity testing
- Metrics endpoint validation
- Network policy compliance verification
- Detailed HTTP statistics

**Dependencies**:
- `kubectl` - Kubernetes cluster management
- `nicolaka/netshoot` - Network debugging container image

### `check-flux-ready.sh` - Flux CD Status Verification

**Purpose**: Verify Flux CD readiness and sync status across all components.

**What it does**:
- Checks Flux CD system components status
- Verifies GitRepository sync status
- Validates Kustomization readiness
- Reports overall Flux CD health

**Usage**:
```bash
./scripts/check-flux-ready.sh
```

**Dependencies**:
- `flux` - Flux CD CLI for GitOps management
- `kubectl` - Kubernetes cluster management

## Usage Examples

### Complete Workflow

```bash
# 1. Complete setup with Flux CD GitOps (includes validation)
./scripts/setup-all.sh

# 2. Validate kustomizations (optional - already done in setup)
make kustomize-check

# 3. Check Flux CD status
./scripts/check-flux-ready.sh

# 4. Test metrics endpoint from monitoring namespace
./scripts/debug-metrics-simple.sh

# 5. Generate load and test HPA (choose one)
./scripts/hpa-demo.sh run                    # Standard test
./scripts/hpa-demo.sh aggressive             # Aggressive test (500+ concurrent)
./scripts/hpa-demo.sh burst                  # Burst pattern (extreme uneven distribution)

# 6. Watch HPA scaling
./scripts/hpa-demo.sh watch

# 7. Cleanup everything (Flux-aware)
./scripts/teardown-all.sh
```

### Alternative Makefile Usage

```bash
# Use Makefile targets for individual operations
make start-cluster
make install-flux-cli
make wait-for-flux
make deploy-everything
make flux-status
make cleanup-all
```

## Script Dependencies

### Required Tools
- **kubectl** - Kubernetes cluster management
- **kind** - Local cluster creation
- **docker** - Image building and registry
- **flux** - Flux CD CLI for GitOps management
- **git** - Version control and GitOps workflow
- **make** - Build automation and target management
- **kustomize** - Kustomize build and validation
- **kubeconform** - Kubernetes schema validation

### Optional Tools
- **hey** - Load testing tool (falls back to curl if not available)
- **curl** - HTTP requests and fallback load generation

## Network Architecture

The scripts demonstrate a proper multi-namespace setup managed by Flux CD:

- **App Namespaces**: Application pods, services, and network policies in dev/staging/production/monitoring
- **Monitoring Namespace**: Prometheus stack, Grafana, and cross-namespace access
- **Network Policies**: Default-deny with explicit allow rules for monitoring → app communication
- **Service Discovery**: DNS resolution working across namespace boundaries
- **Flux CD Management**: All namespaces and resources managed via GitOps workflow

## Troubleshooting

### Common Issues

1. **Port 5000 conflicts**: AirPlay Receiver on macOS uses port 5000
   - **Solution**: Scripts automatically handle port conflicts

2. **Flux CD sync issues**: Git repository not accessible
   - **Solution**: Ensure SSH keys are properly configured for GitHub

3. **HPA not scaling**: Metrics-server not installed
   - **Solution**: `setup-all.sh` automatically installs metrics-server

4. **Network policy blocking**: Cross-namespace communication failing
   - **Solution**: `debug-metrics-simple.sh` validates network policies

### Debug Commands

```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Check Flux CD status
flux get sources git
flux get kustomizations

# Check HPA status
kubectl get hpa --all-namespaces
kubectl describe hpa -n dev

# Check network policies
kubectl get networkpolicies --all-namespaces
kubectl describe networkpolicy -n dev
```

## Security Considerations

- All scripts use non-root containers where possible
- Network policies enforce namespace isolation
- Flux CD uses SSH keys for Git authentication
- Debug pods are automatically cleaned up
- No hardcoded secrets in scripts

## Performance Notes

- HPA testing uses configurable load parameters
- Metrics collection optimized for minimal overhead
- Debug pods use lightweight `nicolaka/netshoot` image
- Flux CD reconciliation intervals optimized for development
