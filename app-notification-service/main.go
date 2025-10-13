package main

import (
	"context"
	"encoding/json"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gorilla/mux"
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

// Configuration from environment variables
var (
	failRate       float64
	readyDelay     int
	greeting       string
	startTime      time.Time
	alloyURL       string
	serviceName    string
	serviceVersion string
	environment    string
)

// OpenTelemetry components
var (
	meter        metric.Meter
	tracer       trace.Tracer
	httpRequests metric.Int64Counter
	httpDuration metric.Float64Histogram
)

func init() {
	// Initialize configuration from environment variables
	failRate = getEnvFloat("FAIL_RATE", 0.02)
	readyDelay = getEnvInt("READINESS_DELAY_SEC", 10)
	greeting = getEnvString("GREETING", "hello")
	alloyURL = getEnvString("ALLOY_URL", "grafana-alloy:4318")
	serviceName = getEnvString("SERVICE_NAME", "notification-service")
	serviceVersion = getEnvString("SERVICE_VERSION", "1.0.0")
	environment = getEnvString("ENVIRONMENT", "development")
	startTime = time.Now()

	// Seed random number generator
	rand.Seed(time.Now().UnixNano())

	// Initialize OpenTelemetry
	initOpenTelemetry()
}

func initOpenTelemetry() {
	ctx := context.Background()

	// Create resource with service information
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion(serviceVersion),
			semconv.DeploymentEnvironment(environment),
		),
	)
	if err != nil {
		log.Fatalf("Failed to create resource: %v", err)
	}

	// Initialize tracing
	initTracing(ctx, res)

	// Initialize metrics
	initMetrics(ctx, res)
}

func initTracing(ctx context.Context, res *resource.Resource) {
	// Create OTLP trace exporter
	traceExporter, err := otlptracehttp.New(ctx,
		otlptracehttp.WithEndpoint(alloyURL),
		otlptracehttp.WithInsecure(),
	)
	if err != nil {
		log.Fatalf("Failed to create trace exporter: %v", err)
	}

	// Create trace provider
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
	)

	// Set global trace provider
	otel.SetTracerProvider(tp)

	// Create tracer
	tracer = tp.Tracer(serviceName)
}

func initMetrics(ctx context.Context, res *resource.Resource) {
	// Create OTLP metric exporter
	metricExporter, err := otlpmetrichttp.New(ctx,
		otlpmetrichttp.WithEndpoint(alloyURL),
		otlpmetrichttp.WithInsecure(),
	)
	if err != nil {
		log.Fatalf("Failed to create metric exporter: %v", err)
	}

	// Create meter provider
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter)),
	)

	// Set global meter provider
	otel.SetMeterProvider(mp)

	// Create meter
	meter = mp.Meter(serviceName)

	// Create metrics
	httpRequests, err = meter.Int64Counter(
		"http_requests_total",
		metric.WithDescription("HTTP requests"),
	)
	if err != nil {
		log.Fatalf("Failed to create http_requests_total counter: %v", err)
	}

	httpDuration, err = meter.Float64Histogram(
		"http_request_duration_seconds",
		metric.WithDescription("Request duration in seconds"),
	)
	if err != nil {
		log.Fatalf("Failed to create http_request_duration_seconds histogram: %v", err)
	}
}

// Helper function for structured logging
func logStructured(level, message string, attrs map[string]interface{}) {
	logData := map[string]interface{}{
		"timestamp":   time.Now().UTC().Format(time.RFC3339),
		"level":       level,
		"message":     message,
		"service":     serviceName,
		"version":     serviceVersion,
		"environment": environment,
	}

	// Add additional attributes
	for k, v := range attrs {
		logData[k] = v
	}

	jsonData, _ := json.Marshal(logData)
	log.Println(string(jsonData))
}

// Helper functions for environment variables
func getEnvString(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

func getEnvFloat(key string, defaultValue float64) float64 {
	if value := os.Getenv(key); value != "" {
		if floatValue, err := strconv.ParseFloat(value, 64); err == nil {
			return floatValue
		}
	}
	return defaultValue
}

// Health endpoint
func healthzHandler(w http.ResponseWriter, r *http.Request) {
	ctx, span := tracer.Start(r.Context(), "healthz")
	defer span.End()

	start := time.Now()

	// Add span attributes
	span.SetAttributes(
		attribute.String("http.method", r.Method),
		attribute.String("http.url", r.URL.String()),
		attribute.String("http.route", "/healthz"),
	)

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))

	// Record metrics
	httpRequests.Add(ctx, 1, metric.WithAttributes(
		attribute.String("method", r.Method),
		attribute.String("endpoint", "/healthz"),
		attribute.String("code", "200"),
	))
	httpDuration.Record(ctx, time.Since(start).Seconds(), metric.WithAttributes(
		attribute.String("endpoint", "/healthz"),
		attribute.String("method", r.Method),
	))

	// Add span attributes
	span.SetAttributes(
		attribute.Int("http.status_code", 200),
		attribute.Float64("duration_ms", float64(time.Since(start).Nanoseconds())/1e6),
	)
}

// Readiness endpoint
func readyzHandler(w http.ResponseWriter, r *http.Request) {
	ctx, span := tracer.Start(r.Context(), "readyz")
	defer span.End()

	start := time.Now()

	// Add span attributes
	span.SetAttributes(
		attribute.String("http.method", r.Method),
		attribute.String("http.url", r.URL.String()),
		attribute.String("http.route", "/readyz"),
	)

	elapsed := time.Since(startTime)
	if elapsed < time.Duration(readyDelay)*time.Second {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte("not ready"))

		// Record metrics
		httpRequests.Add(ctx, 1, metric.WithAttributes(
			attribute.String("method", r.Method),
			attribute.String("endpoint", "/readyz"),
			attribute.String("code", "503"),
		))
		httpDuration.Record(ctx, time.Since(start).Seconds(), metric.WithAttributes(
			attribute.String("endpoint", "/readyz"),
			attribute.String("method", r.Method),
		))

		// Add span attributes
		span.SetAttributes(
			attribute.Int("http.status_code", 503),
			attribute.Float64("duration_ms", float64(time.Since(start).Nanoseconds())/1e6),
		)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ready"))

	// Record metrics
	httpRequests.Add(ctx, 1, metric.WithAttributes(
		attribute.String("method", r.Method),
		attribute.String("endpoint", "/readyz"),
		attribute.String("code", "200"),
	))
	httpDuration.Record(ctx, time.Since(start).Seconds(), metric.WithAttributes(
		attribute.String("endpoint", "/readyz"),
		attribute.String("method", r.Method),
	))

	// Add span attributes
	span.SetAttributes(
		attribute.Int("http.status_code", 200),
		attribute.Float64("duration_ms", float64(time.Since(start).Nanoseconds())/1e6),
	)
}

// Send notification endpoint
func sendNotificationHandler(w http.ResponseWriter, r *http.Request) {
	ctx, span := tracer.Start(r.Context(), "send_notification")
	defer span.End()

	start := time.Now()

	// Add span attributes
	span.SetAttributes(
		attribute.String("http.method", r.Method),
		attribute.String("http.url", r.URL.String()),
		attribute.String("http.route", "/notifications/send"),
	)

	// Parse request body
	var req struct {
		UserID   string `json:"user_id"`
		Message  string `json:"message"`
		Channel  string `json:"channel"`
		Priority string `json:"priority"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logStructured("ERROR", "Failed to parse notification request", map[string]interface{}{
			"error":    err.Error(),
			"method":   r.Method,
			"endpoint": "/notifications/send",
		})

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":    false,
			"error": "Invalid request body",
		})

		span.SetAttributes(
			attribute.Int("http.status_code", 400),
			attribute.Float64("duration_ms", float64(time.Since(start).Nanoseconds())/1e6),
			attribute.Bool("notification.success", false),
		)
		return
	}

	// Simulate notification processing
	processingDuration := time.Duration(100+rand.Intn(200)) * time.Millisecond
	time.Sleep(processingDuration)

	// Add processing duration to span
	span.SetAttributes(
		attribute.Float64("notification.processing_duration_ms", float64(processingDuration.Nanoseconds())/1e6),
		attribute.String("notification.user_id", req.UserID),
		attribute.String("notification.channel", req.Channel),
		attribute.String("notification.priority", req.Priority),
	)

	// Simulate failure
	if rand.Float64() < failRate {
		// Log the failure
		logStructured("ERROR", "Notification sending failed", map[string]interface{}{
			"error":                  "simulated notification failure",
			"method":                 r.Method,
			"endpoint":               "/notifications/send",
			"user_id":                req.UserID,
			"channel":                req.Channel,
			"priority":               req.Priority,
			"processing_duration_ms": float64(processingDuration.Nanoseconds()) / 1e6,
		})

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":    false,
			"error": "Failed to send notification",
		})

		// Record metrics
		httpRequests.Add(ctx, 1, metric.WithAttributes(
			attribute.String("method", r.Method),
			attribute.String("endpoint", "/notifications/send"),
			attribute.String("code", "500"),
		))
		httpDuration.Record(ctx, time.Since(start).Seconds(), metric.WithAttributes(
			attribute.String("endpoint", "/notifications/send"),
			attribute.String("method", r.Method),
		))

		// Add span attributes
		span.SetAttributes(
			attribute.Int("http.status_code", 500),
			attribute.Float64("duration_ms", float64(time.Since(start).Nanoseconds())/1e6),
			attribute.Bool("notification.success", false),
		)
		return
	}

	// Log the success
	logStructured("INFO", "Notification sent successfully", map[string]interface{}{
		"method":                 r.Method,
		"endpoint":               "/notifications/send",
		"user_id":                req.UserID,
		"channel":                req.Channel,
		"priority":               req.Priority,
		"processing_duration_ms": float64(processingDuration.Nanoseconds()) / 1e6,
		"message_preview":        req.Message[:min(len(req.Message), 50)],
	})

	// Success response
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"ok":       true,
		"message":  "Notification sent successfully",
		"user_id":  req.UserID,
		"channel":  req.Channel,
		"priority": req.Priority,
		"sent_at":  time.Now().UTC().Format(time.RFC3339),
	})

	// Record metrics
	httpRequests.Add(ctx, 1, metric.WithAttributes(
		attribute.String("method", r.Method),
		attribute.String("endpoint", "/notifications/send"),
		attribute.String("code", "200"),
	))
	httpDuration.Record(ctx, time.Since(start).Seconds(), metric.WithAttributes(
		attribute.String("endpoint", "/notifications/send"),
		attribute.String("method", r.Method),
	))

	// Add span attributes
	span.SetAttributes(
		attribute.Int("http.status_code", 200),
		attribute.Float64("duration_ms", float64(time.Since(start).Nanoseconds())/1e6),
		attribute.Bool("notification.success", true),
	)
}

// Helper function for min
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func main() {
	port := getEnvString("PORT", "8000")

	// Create router
	r := mux.NewRouter()

	// Add routes
	r.HandleFunc("/healthz", healthzHandler).Methods("GET")
	r.HandleFunc("/readyz", readyzHandler).Methods("GET")
	r.HandleFunc("/notifications/send", sendNotificationHandler).Methods("POST")

	// Start server
	log.Printf("Starting server on port %s", port)
	log.Printf("Alloy URL: %s", alloyURL)
	log.Printf("Service: %s v%s (%s)", serviceName, serviceVersion, environment)
	log.Printf("Configuration: failRate=%.2f, readyDelay=%ds, greeting=%s", failRate, readyDelay, greeting)

	// Log startup
	logStructured("INFO", "Notification service started successfully", map[string]interface{}{
		"port":            port,
		"alloy_url":       alloyURL,
		"fail_rate":       failRate,
		"ready_delay_sec": readyDelay,
		"service_type":    "notification",
	})

	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatal("Server failed to start:", err)
	}
}
