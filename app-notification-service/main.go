package main

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/faidon-laboratory/go-logging"
	"github.com/gorilla/mux"
)

// Configuration from environment variables
var (
	failRate   float64
	readyDelay int
	greeting   string
	startTime  time.Time
	logger     *logging.Logger
)

func init() {
	// Initialize configuration from environment variables
	failRate = getEnvFloat("FAIL_RATE", 0.02)
	readyDelay = getEnvInt("READINESS_DELAY_SEC", 10)
	greeting = getEnvString("GREETING", "hello")
	startTime = time.Now()

	// Seed random number generator
	rand.Seed(time.Now().UnixNano())

	// Initialize logger
	logger = logging.New(logging.Config{
		ServiceName: getEnvString("SERVICE_NAME", "notification-service"),
		Version:     getEnvString("SERVICE_VERSION", "1.0.0"),
		Environment: getEnvString("ENVIRONMENT", "development"),
		AlloyURL:    getEnvString("ALLOY_URL", "grafana-alloy.monitoring.svc.cluster.local:4318"),
	})
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
	ctx, endSpan := logger.StartSpan(r.Context(), "healthz")
	defer endSpan()

	start := time.Now()

	logger.Info(ctx, "Health check requested")

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))

	// Record metrics
	logger.CountRequest(ctx, "/healthz", 200)
	logger.RecordDuration(ctx, "/healthz", time.Since(start))
}

// Readiness endpoint
func readyzHandler(w http.ResponseWriter, r *http.Request) {
	ctx, endSpan := logger.StartSpan(r.Context(), "readyz")
	defer endSpan()

	start := time.Now()

	elapsed := time.Since(startTime)
	if elapsed < time.Duration(readyDelay)*time.Second {
		logger.Warn(ctx, "Service not ready yet", map[string]interface{}{
			"elapsed_seconds":     elapsed.Seconds(),
			"ready_delay_seconds": readyDelay,
		})

		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte("not ready"))

		logger.CountRequest(ctx, "/readyz", 503)
		logger.RecordDuration(ctx, "/readyz", time.Since(start))
		return
	}

	logger.Info(ctx, "Service is ready")

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ready"))

	logger.CountRequest(ctx, "/readyz", 200)
	logger.RecordDuration(ctx, "/readyz", time.Since(start))
}

// Send notification endpoint
func sendNotificationHandler(w http.ResponseWriter, r *http.Request) {
	ctx, endSpan := logger.StartSpan(r.Context(), "send_notification")
	defer endSpan()

	start := time.Now()

	// Parse request body
	var req struct {
		UserID   string `json:"user_id"`
		Message  string `json:"message"`
		Channel  string `json:"channel"`
		Priority string `json:"priority"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Error(ctx, "Failed to parse notification request", err, map[string]interface{}{
			"method":   r.Method,
			"endpoint": "/notifications/send",
		})

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":    false,
			"error": "Invalid request body",
		})

		logger.CountRequest(ctx, "/notifications/send", 400)
		logger.RecordDuration(ctx, "/notifications/send", time.Since(start))
		return
	}

	logger.Info(ctx, "Processing notification request", map[string]interface{}{
		"user_id":  req.UserID,
		"channel":  req.Channel,
		"priority": req.Priority,
	})

	// Simulate notification processing
	processingDuration := time.Duration(100+rand.Intn(200)) * time.Millisecond
	time.Sleep(processingDuration)

	// Simulate failure
	if rand.Float64() < failRate {
		logger.Error(ctx, "Notification sending failed",
			fmt.Errorf("simulated notification failure"),
			map[string]interface{}{
				"user_id":                req.UserID,
				"channel":                req.Channel,
				"priority":               req.Priority,
				"processing_duration_ms": processingDuration.Milliseconds(),
			})

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":    false,
			"error": "Failed to send notification",
		})

		logger.CountRequest(ctx, "/notifications/send", 500)
		logger.RecordDuration(ctx, "/notifications/send", time.Since(start))
		return
	}

	// Log the success
	logger.Info(ctx, "Notification sent successfully", map[string]interface{}{
		"user_id":                req.UserID,
		"channel":                req.Channel,
		"priority":               req.Priority,
		"processing_duration_ms": processingDuration.Milliseconds(),
		"message_preview":        truncateString(req.Message, 50),
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

	logger.CountRequest(ctx, "/notifications/send", 200)
	logger.RecordDuration(ctx, "/notifications/send", time.Since(start))
}

// Helper function to truncate string
func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
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
	logger.Info(context.Background(), "Notification service started successfully", map[string]interface{}{
		"port":            port,
		"fail_rate":       failRate,
		"ready_delay_sec": readyDelay,
		"service_type":    "notification",
	})

	if err := http.ListenAndServe(":"+port, r); err != nil {
		logger.Error(context.Background(), "Server failed to start", err)
	}
}
