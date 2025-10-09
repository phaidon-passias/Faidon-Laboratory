# Demo App Go - Kubernetes & GitOps Solution

A Go implementation of the demo application with the same functionality as the Python version, demonstrating multi-language support in Kubernetes deployments.

## 🎯 Features

- **Health Endpoints**: `/healthz` and `/readyz` for Kubernetes health checks
- **Work Endpoint**: `/work` with configurable failure rate and latency simulation
- **Metrics Endpoint**: `/metrics` with Prometheus metrics
- **Environment Configuration**: Configurable via environment variables
- **Production Ready**: Non-root user, minimal container image

## 🚀 Quick Start

### **Local Development**
```bash
# Navigate to the Go app directory
cd app-go

# Download dependencies
go mod download

# Run locally
go run main.go

# Test endpoints
curl http://localhost:8000/healthz
curl http://localhost:8000/readyz
curl http://localhost:8000/work
curl http://localhost:8000/metrics
```

### **Docker Build**
```bash
# Build the Docker image
docker build -t demo-app-go:latest .

# Run the container
docker run -p 8000:8000 demo-app-go:latest
```

## ⚙️ Configuration

The application supports the following environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `FAIL_RATE` | `0.02` | Failure rate for `/work` endpoint (0.0-1.0) |
| `READINESS_DELAY_SEC` | `10` | Seconds to wait before becoming ready |
| `GREETING` | `"hello"` | Greeting message returned by `/work` |
| `PORT` | `"8000"` | Port to listen on |

## 📊 Endpoints

### **Health Check**
```bash
GET /healthz
# Returns: "ok" (200)
```

### **Readiness Check**
```bash
GET /readyz
# Returns: "ready" (200) or "not ready" (503)
# Waits for READINESS_DELAY_SEC before becoming ready
```

### **Work Endpoint**
```bash
GET /work
# Returns: {"ok": true, "greeting": "hello"} (200)
# Or: {"ok": false, "error": "simulated failure"} (500)
# Simulates 50-200ms latency
```

### **Metrics**
```bash
GET /metrics
# Returns: Prometheus metrics in text format
```

## 🔧 Prometheus Metrics

The application exposes the following metrics:

- **`http_requests_total`**: Counter of HTTP requests by method, endpoint, and status code
- **`http_request_duration_seconds`**: Histogram of request duration by endpoint and method

## 🏗️ Architecture

### **Dependencies**
- **Gorilla Mux**: HTTP router and URL matcher
- **Prometheus Client**: Metrics collection and exposition
- **Go 1.21**: Latest stable Go version

### **Container Security**
- **Multi-stage build**: Minimal final image size
- **Non-root user**: Runs as user ID 10001
- **Alpine Linux**: Minimal base image for security
- **No shell access**: Reduced attack surface

## 🆚 Comparison with Python Version

| Feature | Go Version | Python Version |
|---------|------------|----------------|
| **Runtime** | Compiled binary | Interpreted |
| **Memory Usage** | Lower | Higher |
| **Startup Time** | Faster | Slower |
| **Image Size** | Smaller | Larger |
| **Dependencies** | Minimal | More |
| **Type Safety** | Static typing | Dynamic typing |

## 🚀 Deployment

The Go application can be deployed using the same Kubernetes manifests as the Python version, with the following changes:

1. **Update image reference** in deployment manifests
2. **Build and push** the Go container image
3. **Deploy** using the existing GitOps pipeline

## 📈 Performance Benefits

- **Lower memory footprint**: ~10-20MB vs ~50-100MB for Python
- **Faster startup**: ~100ms vs ~1-2s for Python
- **Better concurrency**: Native goroutines vs Python threading
- **Smaller images**: ~20MB vs ~100MB+ for Python

## 🔍 Development

### **Code Structure**
```
app-go/
├── main.go          # Main application code
├── go.mod           # Go module definition
├── go.sum           # Dependency checksums
├── Dockerfile       # Container build instructions
└── README.md        # This file
```

### **Key Components**
- **Configuration**: Environment variable parsing
- **Metrics**: Prometheus metrics collection
- **Routing**: HTTP endpoint handling
- **Error Handling**: Graceful error responses

---

**This Go implementation provides the same functionality as the Python version while demonstrating the benefits of compiled languages in containerized environments.**
