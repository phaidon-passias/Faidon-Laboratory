#!/bin/bash

# Build script for Demo App Go
# This script builds the Go application and creates a Docker image

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="api-gateway"
APP_DIR="applications/api-gateway"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-localhost:5000}"

echo -e "${BLUE}🚀 Building API Gateway${NC}"
echo -e "${BLUE}======================${NC}"

# Check if we're in the right directory
if [ ! -d "$APP_DIR" ]; then
    echo -e "${RED}❌ Error: $APP_DIR directory not found${NC}"
    echo -e "${YELLOW}💡 Make sure you're running this script from the project root${NC}"
    exit 1
fi

# Navigate to the Go app directory
cd "$APP_DIR"

echo -e "${BLUE}📁 Working directory: $(pwd)${NC}"

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}❌ Error: Go is not installed${NC}"
    echo -e "${YELLOW}💡 Please install Go 1.21 or later${NC}"
    exit 1
fi

# Check Go version
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
echo -e "${GREEN}✅ Go version: $GO_VERSION${NC}"

# Download dependencies
echo -e "${BLUE}📦 Downloading Go dependencies...${NC}"
go mod download

# Verify dependencies
echo -e "${BLUE}🔍 Verifying dependencies...${NC}"
go mod verify

# Run tests (if any)
if [ -f "*_test.go" ]; then
    echo -e "${BLUE}🧪 Running tests...${NC}"
    go test ./...
fi

# Build the application
echo -e "${BLUE}🔨 Building Go application...${NC}"
CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Go application built successfully${NC}"
else
    echo -e "${RED}❌ Failed to build Go application${NC}"
    exit 1
fi

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}⚠️  Docker not found, skipping image build${NC}"
    echo -e "${GREEN}✅ Go application built successfully at: $(pwd)/main${NC}"
    exit 0
fi

# Build Docker image
echo -e "${BLUE}🐳 Building Docker image...${NC}"
docker build -t "$APP_NAME:$IMAGE_TAG" .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Docker image built successfully: $APP_NAME:$IMAGE_TAG${NC}"
else
    echo -e "${RED}❌ Failed to build Docker image${NC}"
    exit 1
fi

# Tag for local registry
echo -e "${BLUE}🏷️  Tagging image for local registry...${NC}"
docker tag "$APP_NAME:$IMAGE_TAG" "$REGISTRY/$APP_NAME:$IMAGE_TAG"

# Push to local registry (if running)
if docker info &> /dev/null && docker ps | grep -q registry; then
    echo -e "${BLUE}📤 Pushing to local registry...${NC}"
    docker push "$REGISTRY/$APP_NAME:$IMAGE_TAG"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Image pushed to registry: $REGISTRY/$APP_NAME:$IMAGE_TAG${NC}"
    else
        echo -e "${YELLOW}⚠️  Failed to push to registry (registry might not be running)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Local registry not running, skipping push${NC}"
fi

# Display image information
echo -e "${BLUE}📊 Image Information:${NC}"
docker images "$APP_NAME:$IMAGE_TAG" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

echo -e "${GREEN}🎉 Build completed successfully!${NC}"
echo -e "${BLUE}💡 To run the container: docker run -p 8000:8000 $APP_NAME:$IMAGE_TAG${NC}"
echo -e "${BLUE}💡 To test: curl http://localhost:8000/healthz${NC}"
