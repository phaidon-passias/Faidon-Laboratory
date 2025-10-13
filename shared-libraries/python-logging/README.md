# Python Logging Library

A simple, structured logging library with OpenTelemetry integration for microservices.

## Features

- **Structured Logging**: JSON-formatted logs with consistent fields
- **OpenTelemetry Integration**: Automatic trace correlation and metrics
- **Simple API**: Easy-to-use functions for common logging patterns
- **Zero Configuration**: Works out of the box with sensible defaults

## Quick Start

```python
from faidon_laboratory_logging import Logger, Config

# Create logger
logger = Logger(Config(
    service_name="my-service",
    version="1.0.0",
    environment="production",
    alloy_url="grafana-alloy.monitoring.svc.cluster.local:4318"
))

# Simple logging
logger.info("User logged in", user_id="123", ip="192.168.1.1")

# Error logging
try:
    process_user()
except Exception as e:
    logger.error("Failed to process user", e, user_id="123")

# Metrics
logger.count_request("/login", 200)
logger.record_duration("/login", 0.15)

# Tracing
with logger.start_span("process_user") as span:
    logger.add_span_event("user_validation_complete", user_id="123")
```

## Configuration

```python
@dataclass
class Config:
    service_name: str      # Required: Name of your service
    version: str          # Required: Version of your service
    environment: str      # Required: Environment (dev, staging, production)
    alloy_url: str        # Optional: OpenTelemetry endpoint (enables tracing/metrics)
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

1. Install the package:
```bash
pip install -e ../shared-libraries/python-logging
```

2. Import and use:
```python
from faidon_laboratory_logging import Logger, Config

logger = Logger(Config(
    service_name="user-service",
    version="1.0.0",
    environment="development",
    alloy_url="grafana-alloy.monitoring.svc.cluster.local:4318"
))

# Use logger throughout your service
```

## Best Practices

1. **Use structured fields**: Pass data as keyword arguments
2. **Include relevant IDs**: Add `user_id`, `request_id`, etc. to logs
3. **Don't log sensitive data**: Avoid passwords, tokens, PII
4. **Use appropriate log levels**: INFO for normal flow, ERROR for failures
5. **Use context managers**: For spans, use `with logger.start_span():`

## Migration from Existing Logging

Replace your current logging:

```python
# Before
print(f"User {user_id} logged in from {ip}")

# After
logger.info("User logged in", user_id=user_id, ip=ip)
```

This provides better searchability and trace correlation in Grafana.

## Flask Integration Example

```python
from flask import Flask, request
from faidon_laboratory_logging import Logger, Config

app = Flask(__name__)
logger = Logger(Config(
    service_name="user-service",
    version="1.0.0",
    environment="production",
    alloy_url="grafana-alloy.monitoring.svc.cluster.local:4318"
))

@app.route("/users/<user_id>")
def get_user(user_id):
    with logger.start_span("get_user") as span:
        logger.info("Getting user", user_id=user_id)
        
        try:
            user = fetch_user(user_id)
            logger.count_request("/users", 200)
            return user
        except Exception as e:
            logger.error("Failed to get user", e, user_id=user_id)
            logger.count_request("/users", 500)
            raise
```
