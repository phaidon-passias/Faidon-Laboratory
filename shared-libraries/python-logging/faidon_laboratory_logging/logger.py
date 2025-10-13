import json
import time
from typing import Dict, Any, Optional
from dataclasses import dataclass

from opentelemetry import trace, metrics


class DummySpan:
    """Dummy span that acts as a context manager when OpenTelemetry is not initialized"""
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        pass
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.semconv.resource import ResourceAttributes


@dataclass
class Config:
    """Configuration for the logger"""
    service_name: str
    version: str
    environment: str
    alloy_url: Optional[str] = None


class Logger:
    """Structured logging with OpenTelemetry integration"""
    
    def __init__(self, config: Config):
        self.service_name = config.service_name
        self.version = config.version
        self.environment = config.environment
        self.initialized = False
        
        # Initialize OpenTelemetry if AlloyURL is provided
        if config.alloy_url:
            self._init_opentelemetry(config.alloy_url)
    
    def _init_opentelemetry(self, alloy_url: str):
        """Initialize OpenTelemetry components"""
        try:
            # Create resource
            resource = Resource.create({
                ResourceAttributes.SERVICE_NAME: self.service_name,
                ResourceAttributes.SERVICE_VERSION: self.version,
                ResourceAttributes.DEPLOYMENT_ENVIRONMENT: self.environment,
            })
            
            # Initialize tracing
            self._init_tracing(resource, alloy_url)
            
            # Initialize metrics
            self._init_metrics(resource, alloy_url)
            
            self.initialized = True
            
        except Exception as e:
            print(f"Failed to initialize OpenTelemetry: {e}")
    
    def _init_tracing(self, resource: Resource, alloy_url: str):
        """Initialize tracing"""
        try:
            # Create OTLP trace exporter
            trace_exporter = OTLPSpanExporter(
                endpoint=f"http://{alloy_url}/v1/traces",
            )
            
            # Create tracer provider
            tracer_provider = TracerProvider(resource=resource)
            tracer_provider.add_span_processor(
                BatchSpanProcessor(trace_exporter)
            )
            
            # Set global tracer provider
            trace.set_tracer_provider(tracer_provider)
            
            # Create tracer
            self.tracer = trace.get_tracer(self.service_name)
            
        except Exception as e:
            print(f"Failed to initialize tracing: {e}")
            self.tracer = None
    
    def _init_metrics(self, resource: Resource, alloy_url: str):
        """Initialize metrics"""
        try:
            # Create OTLP metric exporter
            metric_exporter = OTLPMetricExporter(
                endpoint=f"http://{alloy_url}/v1/metrics",
            )
            
            # Create meter provider
            meter_provider = MeterProvider(
                resource=resource,
                metric_readers=[
                    PeriodicExportingMetricReader(metric_exporter)
                ]
            )
            
            # Set global meter provider
            metrics.set_meter_provider(meter_provider)
            
            # Create meter
            self.meter = metrics.get_meter(self.service_name)
            
            # Create metrics
            self.request_counter = self.meter.create_counter(
                name="http_requests_total",
                description="HTTP requests"
            )
            
            self.request_duration = self.meter.create_histogram(
                name="http_request_duration_seconds",
                description="Request duration in seconds"
            )
            
        except Exception as e:
            print(f"Failed to initialize metrics: {e}")
            self.request_counter = None
            self.request_duration = None
    
    # Logging functions
    
    def info(self, message: str, **fields):
        """Log an info message"""
        self._log("INFO", message, fields)
    
    def error(self, message: str, error: Exception, **fields):
        """Log an error message"""
        fields["error"] = str(error)
        self._log("ERROR", message, fields)
    
    def warn(self, message: str, **fields):
        """Log a warning message"""
        self._log("WARN", message, fields)
    
    def debug(self, message: str, **fields):
        """Log a debug message"""
        self._log("DEBUG", message, fields)
    
    def _log(self, level: str, message: str, fields: Dict[str, Any]):
        """Internal logging function"""
        log_data = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "level": level,
            "message": message,
            "service": self.service_name,
            "version": self.version,
            "environment": self.environment,
            **fields
        }
        
        # Add trace context automatically
        if self.initialized:
            span = trace.get_current_span()
            if span and span.is_recording():
                span_context = span.get_span_context()
                log_data["trace_id"] = format(span_context.trace_id, '032x')
                log_data["span_id"] = format(span_context.span_id, '016x')
        
        # Send to stdout (will be collected by Loki)
        print(json.dumps(log_data))
    
    # Metric functions
    
    def count_request(self, endpoint: str, status_code: int):
        """Increment the request counter"""
        if self.initialized and self.request_counter:
            self.request_counter.add(1, {
                "endpoint": endpoint,
                "status_code": str(status_code),
                "service": self.service_name
            })
    
    def record_duration(self, endpoint: str, duration_seconds: float):
        """Record request duration"""
        if self.initialized and self.request_duration:
            self.request_duration.record(duration_seconds, {
                "endpoint": endpoint,
                "service": self.service_name
            })
    
    # Tracing functions
    
    def start_span(self, operation: str):
        """Start a new span"""
        if self.initialized and self.tracer:
            span = self.tracer.start_span(operation)
            span.set_attributes({
                "service": self.service_name,
                "version": self.version,
                "environment": self.environment
            })
            return span
        # Return a dummy context manager if not initialized
        return DummySpan()
    
    def add_span_event(self, event: str, **fields):
        """Add an event to the current span"""
        if self.initialized:
            span = trace.get_current_span()
            if span and span.is_recording():
                span.add_event(event, fields)
    
    def add_span_attribute(self, key: str, value: str):
        """Add an attribute to the current span"""
        if self.initialized:
            span = trace.get_current_span()
            if span and span.is_recording():
                span.set_attribute(key, value)
