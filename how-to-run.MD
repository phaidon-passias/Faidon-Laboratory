# How to Run the Kaiko Assignment

This guide provides step-by-step instructions for running the complete Kubernetes and GitOps solution for the Kaiko Assignment.

## 📋 Table of Contents

- [🛠️ Prerequisites](#️-prerequisites)
- [🚀 Quick Start](#-quick-start)
- [📋 Detailed Steps](#-detailed-steps)
- [🔍 Verification](#-verification)
- [🧪 Testing](#-testing)
- [📊 Monitoring Access](#-monitoring-access)
- [🧹 Cleanup](#-cleanup)
- [❓ Troubleshooting](#-troubleshooting)

**📚 Related Documentation:**
- **[README.md](../README.md)** - Technical implementation details and assignment completion status
- **[design-decisions.md](../design-decisions.md)** - Architectural decisions and trade-offs analysis
- **[scripts/SCRIPTS.md](SCRIPTS.md)** - Detailed script documentation and technical reference

## Prerequisites

- **macOS/Linux** with shell access
- **Docker Desktop** installed and running
- **Git** for version control
- **Required tools**: kind, kubectl, flux, kustomize, kubeconform, hey (installed via `make install-tools`)

## Quick Start

### 1. Initial Setup
```bash
# Install all required tools (kind, kubectl, flux, kustomize, kubeconform, hey)
make install-tools

# Complete environment setup (creates cluster, installs Flux, deploys everything)
make setup-all
```

### 2. Validate Configuration (Optional)
```bash
# Validate kustomizations (already done in setup, but can run independently)
make kustomize-check

# Individual validation steps
make kustomize-build          # Build all kustomizations
make kustomize-validate       # Schema validation with kubeconform
```

### 3. Verify Deployment
```bash
# Check overall cluster and application status
make cluster-status

# Check GitOps (Flux) status
make flux-status
```

### 4. Test Application Functionality
```bash
# Test cross-namespace metrics and monitoring
make debug-metrics

# Demonstrate HPA (Horizontal Pod Autoscaler) with load testing
make hpa-demo
```

### 5. Cleanup
```bash
# Complete environment cleanup
make teardown-all
```

---

## Detailed Usage Guide

### `make install-tools`
**When to use**: First time setup or when tools are missing
**Installs**: kind, kubectl, flux, kustomize, kubeconform, hey, kubectx

### `make setup-all`
**When to use**: Initial setup or after complete teardown
**Includes**: Automatic kustomize validation (step 4/7)

### `make cluster-status`
**When to use**: Regular health checks, troubleshooting, or after deployments

### `make flux-status`
**When to use**: After making changes, troubleshooting GitOps issues

### `make kustomize-check`
**When to use**: After making configuration changes, before deployment, CI/CD validation
**What it does**: Complete validation (structure + build + schema validation)

### `make kustomize-build`
**When to use**: Testing kustomization builds, debugging configuration issues
**What it does**: Builds all kustomizations (infrastructure, applications, bootstrap)

### `make kustomize-validate`
**When to use**: Schema validation, ensuring Kubernetes compliance
**What it does**: Validates generated resources against Kubernetes schemas using kubeconform

### `make kustomize-lint`
**When to use**: Code quality checks, best practices validation
**What it does**: Lints kustomizations for best practices and schema compliance

### `make debug-metrics`
**When to use**: Testing monitoring setup, validating cross-namespace communication

### `make debug-monitoring`
**When to use**: Advanced debugging, manual monitoring investigation

### `make hpa-demo`
**When to use**: Demonstrating auto-scaling, testing application performance under load

### `make deploy-via-flux`
**When to use**: After making configuration changes, deploying updates

### `make teardown-all`
**When to use**: Complete cleanup, starting fresh, or when done with the assignment
