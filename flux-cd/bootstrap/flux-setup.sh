#!/bin/bash

# FluxCD Setup Script
# Installs FluxCD CLI and bootstraps FluxCD to the cluster

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Configuration
CLUSTER_NAME="kind-kaiko-lab"
GITHUB_USER="phaidon-passias"
GITHUB_REPO="kaiko-assignment"
GITHUB_BRANCH="main"
FLUX_NAMESPACE="flux-system"

print_header "FluxCD Setup and Bootstrap"
print_status "Target cluster: $CLUSTER_NAME"
print_status "GitHub repository: $GITHUB_USER/$GITHUB_REPO"
print_status "GitHub branch: $GITHUB_BRANCH"
print_status "Flux namespace: $FLUX_NAMESPACE"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we're connected to a cluster
if ! kubectl cluster-info &> /dev/null; then
    print_error "Not connected to a Kubernetes cluster"
    print_status "Please ensure your Kind cluster is running:"
    echo "  make start-cluster"
    exit 1
fi

# Check if FluxCD CLI is installed
if ! command -v flux &> /dev/null; then
    print_header "Installing FluxCD CLI"
    print_status "FluxCD CLI not found. Installing..."
    
    # Try different installation methods
    if command -v brew &> /dev/null; then
        print_status "Installing via Homebrew..."
        brew install fluxcd/tap/flux
    elif command -v curl &> /dev/null; then
        print_status "Installing via install script..."
        curl -s https://fluxcd.io/install.sh | sudo bash
    else
        print_error "No suitable installation method found"
        print_status "Please install FluxCD CLI manually:"
        echo "  brew install fluxcd/tap/flux"
        echo "  or visit: https://fluxcd.io/docs/installation/"
        exit 1
    fi
    
    # Verify installation
    if ! command -v flux &> /dev/null; then
        print_error "FluxCD CLI installation failed"
        exit 1
    fi
    
    print_status "FluxCD CLI installed successfully"
else
    print_status "FluxCD CLI already installed"
fi

# Check FluxCD version
print_status "FluxCD CLI version:"
flux version

# Check if FluxCD is already bootstrapped
if kubectl get namespace $FLUX_NAMESPACE &> /dev/null; then
    print_warning "FluxCD namespace '$FLUX_NAMESPACE' already exists"
    print_status "Checking if FluxCD is already bootstrapped..."
    
    if kubectl get gitrepositories -n $FLUX_NAMESPACE &> /dev/null; then
        print_status "FluxCD appears to be already bootstrapped"
        print_status "Skipping bootstrap step"
    else
        print_status "FluxCD namespace exists but not bootstrapped, proceeding with bootstrap..."
    fi
else
    print_header "Bootstrapping FluxCD"
    print_status "Bootstrapping FluxCD to namespace '$FLUX_NAMESPACE'..."
    
    # Bootstrap FluxCD
    flux bootstrap git \
        --url=ssh://git@github.com/$GITHUB_USER/$GITHUB_REPO \
        --branch=$GITHUB_BRANCH \
        --path=flux-cd/bootstrap \
        --namespace=$FLUX_NAMESPACE \
        --components-extra=image-reflector-controller,image-automation-controller
    
    print_status "FluxCD bootstrap completed successfully"
fi

# Verify FluxCD installation
print_header "Verifying FluxCD Installation"
print_status "Checking FluxCD controllers..."

kubectl get pods -n $FLUX_NAMESPACE

print_status "Checking FluxCD custom resources..."

kubectl get crd | grep flux

print_status "FluxCD setup completed successfully!"

print_header "Next Steps"
print_status "1. Commit and push your repository structure to GitHub"
print_status "2. FluxCD will automatically detect and apply changes"
print_status "3. Check FluxCD status with: flux get sources git"
print_status "4. Check FluxCD logs with: flux logs --follow"
