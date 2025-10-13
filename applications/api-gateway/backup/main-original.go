package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gorilla/mux"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
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
	failRate               float64
	readyDelay             int
	greeting               string
	startTime              time.Time
	alloyURL               string
	serviceName            string
	serviceVersion         string
	environment            string
	userServiceURL         string
	notificationServiceURL string
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
	serviceName = getEnvString("SERVICE_NAME", "api-gateway")
	serviceVersion = getEnvString("SERVICE_VERSION", "1.0.0")
	environment = getEnvString("ENVIRONMENT", "development")
	userServiceURL = getEnvString("USER_SERVICE_URL", "http://user-service:80")
	notificationServiceURL = getEnvString("NOTIFICATION_SERVICE_URL", "http://notification-service:80")
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

// Process user request endpoint - calls user service and notification service
func processUserHandler(w http.ResponseWriter, r *http.Request) {
	ctx, span := tracer.Start(r.Context(), "process_user_request")
	defer span.End()

	start := time.Now()

	// Add span attributes
	span.SetAttributes(
		attribute.String("http.method", r.Method),
		attribute.String("http.url", r.URL.String()),
		attribute.String("http.route", "/process-user"),
	)

	// Parse request body
	var req struct {
		UserID  string `json:"user_id"`
		Action  string `json:"action"`
		Message string `json:"message"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logStructured("ERROR", "Failed to parse user request", map[string]interface{}{
			"error":    err.Error(),
			"method":   r.Method,
			"endpoint": "/process-user",
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
			attribute.Bool("process_user.success", false),
		)
		return
	}

	// Add request details to span
	span.SetAttributes(
		attribute.String("user.id", req.UserID),
		attribute.String("user.action", req.Action),
	)

	// Step 1: Call User Service
	userServiceResult, err := callUserService(ctx, req.UserID, req.Action)
	if err != nil {
		logStructured("ERROR", "User service call failed", map[string]interface{}{
			"error":    err.Error(),
			"user_id":  req.UserID,
			"action":   req.Action,
			"method":   r.Method,
			"endpoint": "/process-user",
		})

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":    false,
			"error": "User service unavailable",
		})

		span.SetAttributes(
			attribute.Int("http.status_code", 500),
			attribute.Float64("duration_ms", float64(time.Since(start).Nanoseconds())/1e6),
			attribute.Bool("process_user.success", false),
			attribute.Bool("user_service.success", false),
		)
		return
	}

	// Step 2: Call Notification Service
	notificationResult, err := callNotificationService(ctx, req.UserID, req.Message, userServiceResult)
	if err != nil {
		logStructured("ERROR", "Notification service call failed", map[string]interface{}{
			"error":    err.Error(),
			"user_id":  req.UserID,
			"action":   req.Action,
			"method":   r.Method,
			"endpoint": "/process-user",
		})

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":    false,
			"error": "Notification service unavailable",
		})

		span.SetAttributes(
			attribute.Int("http.status_code", 500),
			attribute.Float64("duration_ms", float64(time.Since(start).Nanoseconds())/1e6),
			attribute.Bool("process_user.success", false),
			attribute.Bool("user_service.success", true),
			attribute.Bool("notification_service.success", false),
		)
		return
	}

	// Log the success
	logStructured("INFO", "User request processed successfully", map[string]interface{}{
		"method":              r.Method,
		"endpoint":            "/process-user",
		"user_id":             req.UserID,
		"action":              req.Action,
		"user_service_result": userServiceResult,
		"notification_result": notificationResult,
		"total_duration_ms":   float64(time.Since(start).Nanoseconds()) / 1e6,
	})

	// Success response
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"ok":                  true,
		"message":             "User request processed successfully",
		"user_id":             req.UserID,
		"action":              req.Action,
		"user_service_result": userServiceResult,
		"notification_result": notificationResult,
		"processed_at":        time.Now().UTC().Format(time.RFC3339),
	})

	// Record metrics
	httpRequests.Add(ctx, 1, metric.WithAttributes(
		attribute.String("method", r.Method),
		attribute.String("endpoint", "/process-user"),
		attribute.String("code", "200"),
	))
	httpDuration.Record(ctx, time.Since(start).Seconds(), metric.WithAttributes(
		attribute.String("endpoint", "/process-user"),
		attribute.String("method", r.Method),
	))

	// Add span attributes
	span.SetAttributes(
		attribute.Int("http.status_code", 200),
		attribute.Float64("duration_ms", float64(time.Since(start).Nanoseconds())/1e6),
		attribute.Bool("process_user.success", true),
		attribute.Bool("user_service.success", true),
		attribute.Bool("notification_service.success", true),
	)
}

// Call User Service (Python service)
func callUserService(ctx context.Context, userID, action string) (string, error) {
	ctx, span := tracer.Start(ctx, "call_user_service")
	defer span.End()

	span.SetAttributes(
		attribute.String("user_service.url", userServiceURL),
		attribute.String("user_service.endpoint", "/work"),
		attribute.String("user.id", userID),
		attribute.String("user.action", action),
	)

	// Create HTTP client with OpenTelemetry instrumentation
	client := &http.Client{
		Transport: otelhttp.NewTransport(http.DefaultTransport),
		Timeout:   5 * time.Second,
	}

	// Create request
	req, err := http.NewRequestWithContext(ctx, "GET", userServiceURL+"/work", nil)
	if err != nil {
		span.SetAttributes(attribute.Bool("user_service.success", false))
		return "", err
	}

	// Make request
	resp, err := client.Do(req)
	if err != nil {
		span.SetAttributes(attribute.Bool("user_service.success", false))
		return "", err
	}
	defer resp.Body.Close()

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		span.SetAttributes(attribute.Bool("user_service.success", false))
		return "", err
	}

	span.SetAttributes(
		attribute.Int("user_service.status_code", resp.StatusCode),
		attribute.Bool("user_service.success", resp.StatusCode == 200),
	)

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("user service returned status %d", resp.StatusCode)
	}

	return string(body), nil
}

// Call Notification Service
func callNotificationService(ctx context.Context, userID, message string, userServiceResult string) (string, error) {
	ctx, span := tracer.Start(ctx, "call_notification_service")
	defer span.End()

	span.SetAttributes(
		attribute.String("notification_service.url", notificationServiceURL),
		attribute.String("notification_service.endpoint", "/notifications/send"),
		attribute.String("user.id", userID),
	)

	// Create HTTP client with OpenTelemetry instrumentation
	client := &http.Client{
		Transport: otelhttp.NewTransport(http.DefaultTransport),
		Timeout:   5 * time.Second,
	}

	// Create request body
	reqBody := map[string]interface{}{
		"user_id":  userID,
		"message":  message + " (User service result: " + userServiceResult + ")",
		"channel":  "email",
		"priority": "normal",
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		span.SetAttributes(attribute.Bool("notification_service.success", false))
		return "", err
	}

	// Create request
	req, err := http.NewRequestWithContext(ctx, "POST", notificationServiceURL+"/notifications/send", bytes.NewBuffer(jsonBody))
	if err != nil {
		span.SetAttributes(attribute.Bool("notification_service.success", false))
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	// Make request
	resp, err := client.Do(req)
	if err != nil {
		span.SetAttributes(attribute.Bool("notification_service.success", false))
		return "", err
	}
	defer resp.Body.Close()

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		span.SetAttributes(attribute.Bool("notification_service.success", false))
		return "", err
	}

	span.SetAttributes(
		attribute.Int("notification_service.status_code", resp.StatusCode),
		attribute.Bool("notification_service.success", resp.StatusCode == 200),
	)

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("notification service returned status %d", resp.StatusCode)
	}

	return string(body), nil
}

func main() {
	port := getEnvString("PORT", "8000")

	// Create router
	r := mux.NewRouter()

	// Add routes
	r.HandleFunc("/healthz", healthzHandler).Methods("GET")
	r.HandleFunc("/readyz", readyzHandler).Methods("GET")
	r.HandleFunc("/process-user", processUserHandler).Methods("POST")

	// Start server
	log.Printf("Starting server on port %s", port)
	log.Printf("Alloy URL: %s", alloyURL)
	log.Printf("Service: %s v%s (%s)", serviceName, serviceVersion, environment)
	log.Printf("Configuration: failRate=%.2f, readyDelay=%ds, greeting=%s", failRate, readyDelay, greeting)

	// Log startup
	logStructured("INFO", "API Gateway started successfully", map[string]interface{}{
		"port":                     port,
		"alloy_url":                alloyURL,
		"fail_rate":                failRate,
		"ready_delay_sec":          readyDelay,
		"user_service_url":         userServiceURL,
		"notification_service_url": notificationServiceURL,
		"service_type":             "api-gateway",
	})

	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatal("Server failed to start:", err)
	}
}
