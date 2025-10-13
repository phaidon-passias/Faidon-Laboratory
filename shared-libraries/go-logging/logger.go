package logging

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/metric"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"go.opentelemetry.io/otel/trace"
)

// Logger handles structured logging, metrics, and tracing
type Logger struct {
	serviceName     string
	version         string
	environment     string
	tracer          trace.Tracer
	meter           metric.Meter
	requestCounter  metric.Int64Counter
	requestDuration metric.Float64Histogram
	initialized     bool
}

// Config holds the configuration for the logger
type Config struct {
	ServiceName string
	Version     string
	Environment string
	AlloyURL    string
}

// New creates a new logger instance
func New(config Config) *Logger {
	logger := &Logger{
		serviceName: config.ServiceName,
		version:     config.Version,
		environment: config.Environment,
	}

	// Initialize OpenTelemetry if AlloyURL is provided
	if config.AlloyURL != "" {
		logger.initOpenTelemetry(config.AlloyURL)
	}

	return logger
}

// initOpenTelemetry sets up OpenTelemetry components
func (l *Logger) initOpenTelemetry(alloyURL string) {
	ctx := context.Background()

	// Create resource with service information
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(l.serviceName),
			semconv.ServiceVersion(l.version),
			semconv.DeploymentEnvironment(l.environment),
		),
	)
	if err != nil {
		log.Printf("Failed to create resource: %v", err)
		return
	}

	// Initialize tracing
	l.initTracing(ctx, res, alloyURL)

	// Initialize metrics
	l.initMetrics(ctx, res, alloyURL)

	l.initialized = true
}

// initTracing sets up tracing
func (l *Logger) initTracing(ctx context.Context, res *resource.Resource, alloyURL string) {
	// Create OTLP trace exporter
	traceExporter, err := otlptracehttp.New(ctx,
		otlptracehttp.WithEndpoint(alloyURL),
		otlptracehttp.WithInsecure(),
	)
	if err != nil {
		log.Printf("Failed to create trace exporter: %v", err)
		return
	}

	// Create trace provider
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
	)

	// Set global trace provider
	otel.SetTracerProvider(tp)

	// Create tracer
	l.tracer = tp.Tracer(l.serviceName)
}

// initMetrics sets up metrics
func (l *Logger) initMetrics(ctx context.Context, res *resource.Resource, alloyURL string) {
	// Create OTLP metric exporter
	metricExporter, err := otlpmetrichttp.New(ctx,
		otlpmetrichttp.WithEndpoint(alloyURL),
		otlpmetrichttp.WithInsecure(),
	)
	if err != nil {
		log.Printf("Failed to create metric exporter: %v", err)
		return
	}

	// Create meter provider
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter)),
	)

	// Set global meter provider
	otel.SetMeterProvider(mp)

	// Create meter
	l.meter = mp.Meter(l.serviceName)

	// Create metrics
	l.requestCounter, err = l.meter.Int64Counter(
		"http_requests_total",
		metric.WithDescription("HTTP requests"),
	)
	if err != nil {
		log.Printf("Failed to create http_requests_total counter: %v", err)
	}

	l.requestDuration, err = l.meter.Float64Histogram(
		"http_request_duration_seconds",
		metric.WithDescription("Request duration in seconds"),
	)
	if err != nil {
		log.Printf("Failed to create http_request_duration_seconds histogram: %v", err)
	}
}

// Logging functions

// Info logs an info message
func (l *Logger) Info(ctx context.Context, message string, fields ...map[string]interface{}) {
	l.log(ctx, "INFO", message, fields...)
}

// Error logs an error message
func (l *Logger) Error(ctx context.Context, message string, err error, fields ...map[string]interface{}) {
	allFields := []map[string]interface{}{{"error": err.Error()}}
	allFields = append(allFields, fields...)
	l.log(ctx, "ERROR", message, allFields...)
}

// Warn logs a warning message
func (l *Logger) Warn(ctx context.Context, message string, fields ...map[string]interface{}) {
	l.log(ctx, "WARN", message, fields...)
}

// Debug logs a debug message
func (l *Logger) Debug(ctx context.Context, message string, fields ...map[string]interface{}) {
	l.log(ctx, "DEBUG", message, fields...)
}

// log is the internal logging function
func (l *Logger) log(ctx context.Context, level, message string, fields ...map[string]interface{}) {
	logData := map[string]interface{}{
		"timestamp":   time.Now().UTC().Format(time.RFC3339),
		"level":       level,
		"message":     message,
		"service":     l.serviceName,
		"version":     l.version,
		"environment": l.environment,
	}

	// Add trace context automatically
	if l.initialized && l.tracer != nil {
		if span := trace.SpanFromContext(ctx); span.IsRecording() {
			logData["trace_id"] = span.SpanContext().TraceID().String()
			logData["span_id"] = span.SpanContext().SpanID().String()
		}
	}

	// Merge all fields
	for _, fieldMap := range fields {
		for k, v := range fieldMap {
			logData[k] = v
		}
	}

	// Send to stdout (will be collected by Loki)
	jsonData, _ := json.Marshal(logData)
	log.Println(string(jsonData))
}

// Metric functions

// CountRequest increments the request counter
func (l *Logger) CountRequest(ctx context.Context, endpoint string, statusCode int) {
	if l.initialized && l.requestCounter != nil {
		l.requestCounter.Add(ctx, 1, metric.WithAttributes(
			attribute.String("endpoint", endpoint),
			attribute.String("status_code", fmt.Sprintf("%d", statusCode)),
			attribute.String("service", l.serviceName),
		))
	}
}

// RecordDuration records request duration
func (l *Logger) RecordDuration(ctx context.Context, endpoint string, duration time.Duration) {
	if l.initialized && l.requestDuration != nil {
		l.requestDuration.Record(ctx, duration.Seconds(), metric.WithAttributes(
			attribute.String("endpoint", endpoint),
			attribute.String("service", l.serviceName),
		))
	}
}

// Tracing functions

// StartSpan starts a new span
func (l *Logger) StartSpan(ctx context.Context, operation string) (context.Context, func()) {
	if l.initialized && l.tracer != nil {
		ctx, span := l.tracer.Start(ctx, operation)
		span.SetAttributes(
			attribute.String("service", l.serviceName),
			attribute.String("version", l.version),
			attribute.String("environment", l.environment),
		)

		return ctx, func() {
			span.End()
		}
	}

	// Return no-op if not initialized
	return ctx, func() {}
}

// AddSpanEvent adds an event to the current span
func (l *Logger) AddSpanEvent(ctx context.Context, event string, fields ...map[string]interface{}) {
	if l.initialized && l.tracer != nil {
		if span := trace.SpanFromContext(ctx); span.IsRecording() {
			attrs := []attribute.KeyValue{
				attribute.String("event", event),
			}

			// Convert fields to attributes
			for _, fieldMap := range fields {
				for k, v := range fieldMap {
					attrs = append(attrs, attribute.String(k, fmt.Sprintf("%v", v)))
				}
			}

			span.AddEvent(event, trace.WithAttributes(attrs...))
		}
	}
}

// AddSpanAttribute adds an attribute to the current span
func (l *Logger) AddSpanAttribute(ctx context.Context, key, value string) {
	if l.initialized && l.tracer != nil {
		if span := trace.SpanFromContext(ctx); span.IsRecording() {
			span.SetAttributes(attribute.String(key, value))
		}
	}
}
