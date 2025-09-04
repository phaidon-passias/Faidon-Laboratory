# How to Run the Kaiko Assignment

This guide provides step-by-step instructions for running the complete Kubernetes and GitOps solution for the Kaiko Assignment.

## Prerequisites

- **macOS/Linux** with shell access
- **Docker Desktop** installed and running
- **Git** for version control

## Quick Start

### 1. Initial Setup
```bash
# Install all required tools (kind, kubectl, flux, hey)
make install-tools

# Complete environment setup (creates cluster, installs Flux, deploys everything)
make setup-all
```

### 2. Verify Deployment
```bash
# Check overall cluster and application status
make cluster-status

# Check GitOps (Flux) status
make flux-status
```

### 3. Test Application Functionality
```bash
# Test cross-namespace metrics and monitoring
make debug-metrics

# Demonstrate HPA (Horizontal Pod Autoscaler) with load testing
make hpa-demo
```

### 4. Cleanup
```bash
# Complete environment cleanup
make teardown-all
```

---

## Detailed Usage Guide

### `make install-tools`
**When to use**: First time setup or when tools are missing

### `make setup-all`
**When to use**: Initial setup or after complete teardown

### `make cluster-status`
**When to use**: Regular health checks, troubleshooting, or after deployments

### `make flux-status`
**When to use**: After making changes, troubleshooting GitOps issues

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
