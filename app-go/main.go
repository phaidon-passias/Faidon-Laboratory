package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/faidon-laboratory/go-logging"
	"github.com/gorilla/mux"
)

// Configuration from environment variables
var (
	failRate               float64
	readyDelay             int
	greeting               string
	startTime              time.Time
	userServiceURL         string
	notificationServiceURL string
	logger                 *logging.Logger
)

func init() {
	// Initialize configuration from environment variables
	failRate = getEnvFloat("FAIL_RATE", 0.02)
	readyDelay = getEnvInt("READINESS_DELAY_SEC", 10)
	greeting = getEnvString("GREETING", "hello")
	userServiceURL = getEnvString("USER_SERVICE_URL", "http://demo-app-python:80")
	notificationServiceURL = getEnvString("NOTIFICATION_SERVICE_URL", "http://notification-service:80")
	startTime = time.Now()

	// Initialize logger
	logger = logging.New(logging.Config{
		ServiceName: getEnvString("SERVICE_NAME", "api-gateway"),
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

// Process user request endpoint - calls user service and notification service
func processUserHandler(w http.ResponseWriter, r *http.Request) {
	ctx, endSpan := logger.StartSpan(r.Context(), "process_user_request")
	defer endSpan()

	start := time.Now()

	// Parse request body
	var req struct {
		UserID  string `json:"user_id"`
		Action  string `json:"action"`
		Message string `json:"message"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Error(ctx, "Failed to parse user request", err, map[string]interface{}{
			"method":   r.Method,
			"endpoint": "/process-user",
		})

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":    false,
			"error": "Invalid request body",
		})

		logger.CountRequest(ctx, "/process-user", 400)
		logger.RecordDuration(ctx, "/process-user", time.Since(start))
		return
	}

	logger.Info(ctx, "Processing user request", map[string]interface{}{
		"user_id": req.UserID,
		"action":  req.Action,
	})

	// Step 1: Call User Service
	userServiceResult, err := callUserService(ctx, req.UserID, req.Action)
	if err != nil {
		logger.Error(ctx, "User service call failed", err, map[string]interface{}{
			"user_id": req.UserID,
			"action":  req.Action,
		})

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":    false,
			"error": "User service unavailable",
		})

		logger.CountRequest(ctx, "/process-user", 500)
		logger.RecordDuration(ctx, "/process-user", time.Since(start))
		return
	}

	// Step 2: Call Notification Service
	notificationResult, err := callNotificationService(ctx, req.UserID, req.Message, userServiceResult)
	if err != nil {
		logger.Error(ctx, "Notification service call failed", err, map[string]interface{}{
			"user_id": req.UserID,
			"action":  req.Action,
		})

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":    false,
			"error": "Notification service unavailable",
		})

		logger.CountRequest(ctx, "/process-user", 500)
		logger.RecordDuration(ctx, "/process-user", time.Since(start))
		return
	}

	// Log the success
	logger.Info(ctx, "User request processed successfully", map[string]interface{}{
		"user_id":             req.UserID,
		"action":              req.Action,
		"user_service_result": userServiceResult,
		"notification_result": notificationResult,
		"total_duration_ms":   time.Since(start).Milliseconds(),
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

	logger.CountRequest(ctx, "/process-user", 200)
	logger.RecordDuration(ctx, "/process-user", time.Since(start))
}

// Call User Service (Python service)
func callUserService(ctx context.Context, userID, action string) (string, error) {
	ctx, endSpan := logger.StartSpan(ctx, "call_user_service")
	defer endSpan()

	logger.Info(ctx, "Calling user service", map[string]interface{}{
		"user_id": userID,
		"action":  action,
		"url":     userServiceURL,
	})

	// Create HTTP client
	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	// Create request
	req, err := http.NewRequestWithContext(ctx, "GET", userServiceURL+"/work", nil)
	if err != nil {
		logger.Error(ctx, "Failed to create user service request", err)
		return "", err
	}

	// Make request
	resp, err := client.Do(req)
	if err != nil {
		logger.Error(ctx, "User service request failed", err)
		return "", err
	}
	defer resp.Body.Close()

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		logger.Error(ctx, "Failed to read user service response", err)
		return "", err
	}

	logger.Info(ctx, "User service call completed", map[string]interface{}{
		"status_code":     resp.StatusCode,
		"response_length": len(body),
	})

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("user service returned status %d", resp.StatusCode)
	}

	return string(body), nil
}

// Call Notification Service
func callNotificationService(ctx context.Context, userID, message string, userServiceResult string) (string, error) {
	ctx, endSpan := logger.StartSpan(ctx, "call_notification_service")
	defer endSpan()

	logger.Info(ctx, "Calling notification service", map[string]interface{}{
		"user_id": userID,
		"url":     notificationServiceURL,
	})

	// Create HTTP client
	client := &http.Client{
		Timeout: 5 * time.Second,
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
		logger.Error(ctx, "Failed to marshal notification request", err)
		return "", err
	}

	// Create request
	req, err := http.NewRequestWithContext(ctx, "POST", notificationServiceURL+"/notifications/send", bytes.NewBuffer(jsonBody))
	if err != nil {
		logger.Error(ctx, "Failed to create notification service request", err)
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	// Make request
	resp, err := client.Do(req)
	if err != nil {
		logger.Error(ctx, "Notification service request failed", err)
		return "", err
	}
	defer resp.Body.Close()

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		logger.Error(ctx, "Failed to read notification service response", err)
		return "", err
	}

	logger.Info(ctx, "Notification service call completed", map[string]interface{}{
		"status_code":     resp.StatusCode,
		"response_length": len(body),
	})

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
	logger.Info(context.Background(), "API Gateway started successfully", map[string]interface{}{
		"port":                     port,
		"user_service_url":         userServiceURL,
		"notification_service_url": notificationServiceURL,
		"fail_rate":                failRate,
		"ready_delay_sec":          readyDelay,
		"service_type":             "api-gateway",
	})

	if err := http.ListenAndServe(":"+port, r); err != nil {
		logger.Error(context.Background(), "Server failed to start", err)
	}
}
