# Go Logging Library

A simple, structured logging library with OpenTelemetry integration for microservices.

## Features

- **Structured Logging**: JSON-formatted logs with consistent fields
- **OpenTelemetry Integration**: Automatic trace correlation and metrics
- **Simple API**: Easy-to-use functions for common logging patterns
- **Zero Configuration**: Works out of the box with sensible defaults

## Quick Start

```go
package main

import (
    "context"
    "github.com/faidon-laboratory/go-logging"
)

func main() {
    // Create logger
    logger := logging.New(logging.Config{
        ServiceName: "my-service",
        Version:     "1.0.0",
        Environment: "production",
        AlloyURL:    "grafana-alloy.monitoring.svc.cluster.local:4318",
    })

    // Simple logging
    logger.Info(ctx, "User logged in", map[string]interface{}{
        "user_id": "123",
        "ip": "192.168.1.1",
    })

    // Error logging
    if err != nil {
        logger.Error(ctx, "Failed to process user", err, map[string]interface{}{
            "user_id": "123",
        })
    }

    // Metrics
    logger.CountRequest(ctx, "/login", 200)
    logger.RecordDuration(ctx, "/login", 150*time.Millisecond)

    // Tracing
    ctx, endSpan := logger.StartSpan(ctx, "process_user")
    defer endSpan()

    logger.AddSpanEvent(ctx, "user_validation_complete", map[string]interface{}{
        "user_id": "123",
    })
}
```

## Configuration

```go
type Config struct {
    ServiceName string // Required: Name of your service
    Version     string // Required: Version of your service
    Environment string // Required: Environment (dev, staging, production)
    AlloyURL    string // Optional: OpenTelemetry endpoint (enables tracing/metrics)
}
```

## Log Format

All logs are output in JSON format:

```json
{
    "timestamp": "2024-01-15T10:30:00Z",
    "level": "INFO",
    "message": "User logged in",
    "service": "my-service",
    "version": "1.0.0",
    "environment": "production",
    "trace_id": "abc123...",
    "span_id": "def456...",
    "user_id": "123",
    "ip": "192.168.1.1"
}
```

## Integration with Existing Services

To use this library in your existing services:

1. Add the dependency to your `go.mod`:
```go
require github.com/faidon-laboratory/go-logging v0.1.0

replace github.com/faidon-laboratory/go-logging => ../shared-libraries/go-logging
```

2. Import and use:
```go
import "github.com/faidon-laboratory/go-logging"

func main() {
    logger := logging.New(logging.Config{
        ServiceName: "api-gateway",
        Version:     "1.0.0",
        Environment: "development",
        AlloyURL:    "grafana-alloy.monitoring.svc.cluster.local:4318",
    })
    
    // Use logger throughout your service
}
```

## Best Practices

1. **Always pass context**: Use `ctx context.Context` for trace correlation
2. **Use structured fields**: Pass data as `map[string]interface{}`
3. **Include relevant IDs**: Add `user_id`, `request_id`, etc. to logs
4. **Don't log sensitive data**: Avoid passwords, tokens, PII
5. **Use appropriate log levels**: INFO for normal flow, ERROR for failures

## Migration from Existing Logging

Replace your current logging:

```go
// Before
log.Printf("User %s logged in from %s", userID, ip)

// After
logger.Info(ctx, "User logged in", map[string]interface{}{
    "user_id": userID,
    "ip": ip,
})
```

This provides better searchability and trace correlation in Grafana.
