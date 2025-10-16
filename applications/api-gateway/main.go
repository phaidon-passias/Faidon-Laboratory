package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
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
	userServiceURL = getEnvString("USER_SERVICE_URL", "http://user-service:80")
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

// Business-level API handlers for SLI tracking

// Get user by ID - latency SLI endpoint
func getUserHandler(w http.ResponseWriter, r *http.Request) {
	ctx, endSpan := logger.StartSpan(r.Context(), "get_user")
	defer endSpan()

	start := time.Now()
	vars := mux.Vars(r)
	userID := vars["id"]

	logger.Info(ctx, "Getting user", map[string]interface{}{
		"user_id": userID,
		"method":  r.Method,
	})

	// Call user service to get user data
	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequestWithContext(ctx, "GET", userServiceURL+"/users/"+userID, nil)
	if err != nil {
		logger.Error(ctx, "Failed to create user service request", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "Internal server error"})
		logger.CountRequest(ctx, "/api/users/{id}", 500)
		logger.RecordDuration(ctx, "/api/users/{id}", time.Since(start))
		return
	}

	resp, err := client.Do(req)
	if err != nil {
		logger.Error(ctx, "User service request failed", err)
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "User service unavailable"})
		logger.CountRequest(ctx, "/api/users/{id}", 503)
		logger.RecordDuration(ctx, "/api/users/{id}", time.Since(start))
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		logger.Error(ctx, "Failed to read user service response", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "Internal server error"})
		logger.CountRequest(ctx, "/api/users/{id}", 500)
		logger.RecordDuration(ctx, "/api/users/{id}", time.Since(start))
		return
	}

	if resp.StatusCode == 404 {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "User not found"})
		logger.CountRequest(ctx, "/api/users/{id}", 404)
		logger.RecordDuration(ctx, "/api/users/{id}", time.Since(start))
		return
	}

	if resp.StatusCode != 200 {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "User service error"})
		logger.CountRequest(ctx, "/api/users/{id}", 500)
		logger.RecordDuration(ctx, "/api/users/{id}", time.Since(start))
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(body)

	logger.Info(ctx, "User retrieved successfully", map[string]interface{}{
		"user_id": userID,
		"duration_ms": time.Since(start).Milliseconds(),
	})
	logger.CountRequest(ctx, "/api/users/{id}", 200)
	logger.RecordDuration(ctx, "/api/users/{id}", time.Since(start))
}

// Create user - availability SLI endpoint
func createUserHandler(w http.ResponseWriter, r *http.Request) {
	ctx, endSpan := logger.StartSpan(r.Context(), "create_user")
	defer endSpan()

	start := time.Now()

	var req struct {
		Name  string `json:"name"`
		Email string `json:"email"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Error(ctx, "Failed to parse create user request", err)
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "Invalid request body"})
		logger.CountRequest(ctx, "/api/users", 400)
		logger.RecordDuration(ctx, "/api/users", time.Since(start))
		return
	}

	logger.Info(ctx, "Creating user", map[string]interface{}{
		"name":  req.Name,
		"email": req.Email,
	})

	// Call user service to create user
	client := &http.Client{Timeout: 5 * time.Second}
	reqBody := map[string]interface{}{
		"name":  req.Name,
		"email": req.Email,
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		logger.Error(ctx, "Failed to marshal create user request", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "Internal server error"})
		logger.CountRequest(ctx, "/api/users", 500)
		logger.RecordDuration(ctx, "/api/users", time.Since(start))
		return
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", userServiceURL+"/users", bytes.NewBuffer(jsonBody))
	if err != nil {
		logger.Error(ctx, "Failed to create user service request", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "Internal server error"})
		logger.CountRequest(ctx, "/api/users", 500)
		logger.RecordDuration(ctx, "/api/users", time.Since(start))
		return
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(httpReq)
	if err != nil {
		logger.Error(ctx, "User service request failed", err)
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "User service unavailable"})
		logger.CountRequest(ctx, "/api/users", 503)
		logger.RecordDuration(ctx, "/api/users", time.Since(start))
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		logger.Error(ctx, "Failed to read user service response", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "Internal server error"})
		logger.CountRequest(ctx, "/api/users", 500)
		logger.RecordDuration(ctx, "/api/users", time.Since(start))
		return
	}

	if resp.StatusCode != 201 && resp.StatusCode != 200 {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "User creation failed"})
		logger.CountRequest(ctx, "/api/users", 500)
		logger.RecordDuration(ctx, "/api/users", time.Since(start))
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	w.Write(body)

	logger.Info(ctx, "User created successfully", map[string]interface{}{
		"name":        req.Name,
		"email":       req.Email,
		"duration_ms": time.Since(start).Milliseconds(),
	})
	logger.CountRequest(ctx, "/api/users", 201)
	logger.RecordDuration(ctx, "/api/users", time.Since(start))
}

// Get notifications - throughput SLI endpoint
func getNotificationsHandler(w http.ResponseWriter, r *http.Request) {
	ctx, endSpan := logger.StartSpan(r.Context(), "get_notifications")
	defer endSpan()

	start := time.Now()

	logger.Info(ctx, "Getting notifications", map[string]interface{}{
		"method": r.Method,
	})

	// Call notification service to get notifications
	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequestWithContext(ctx, "GET", notificationServiceURL+"/notifications", nil)
	if err != nil {
		logger.Error(ctx, "Failed to create notification service request", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "Internal server error"})
		logger.CountRequest(ctx, "/api/notifications", 500)
		logger.RecordDuration(ctx, "/api/notifications", time.Since(start))
		return
	}

	resp, err := client.Do(req)
	if err != nil {
		logger.Error(ctx, "Notification service request failed", err)
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "Notification service unavailable"})
		logger.CountRequest(ctx, "/api/notifications", 503)
		logger.RecordDuration(ctx, "/api/notifications", time.Since(start))
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		logger.Error(ctx, "Failed to read notification service response", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "Internal server error"})
		logger.CountRequest(ctx, "/api/notifications", 500)
		logger.RecordDuration(ctx, "/api/notifications", time.Since(start))
		return
	}

	if resp.StatusCode != 200 {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "Notification service error"})
		logger.CountRequest(ctx, "/api/notifications", 500)
		logger.RecordDuration(ctx, "/api/notifications", time.Since(start))
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(body)

	logger.Info(ctx, "Notifications retrieved successfully", map[string]interface{}{
		"duration_ms": time.Since(start).Milliseconds(),
	})
	logger.CountRequest(ctx, "/api/notifications", 200)
	logger.RecordDuration(ctx, "/api/notifications", time.Since(start))
}

// Process workflow - success rate SLI endpoint
func processWorkflowHandler(w http.ResponseWriter, r *http.Request) {
	ctx, endSpan := logger.StartSpan(r.Context(), "process_workflow")
	defer endSpan()

	start := time.Now()

	var req struct {
		WorkflowID string `json:"workflow_id"`
		Data       string `json:"data"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Error(ctx, "Failed to parse workflow request", err)
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "Invalid request body"})
		logger.CountRequest(ctx, "/api/process", 400)
		logger.RecordDuration(ctx, "/api/process", time.Since(start))
		return
	}

	logger.Info(ctx, "Processing workflow", map[string]interface{}{
		"workflow_id": req.WorkflowID,
	})

	// Simulate workflow processing with potential failure
	if rand.Float64() < failRate {
		logger.Error(ctx, "Workflow processing failed", fmt.Errorf("simulated workflow failure"), map[string]interface{}{
			"workflow_id": req.WorkflowID,
		})
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":    false,
			"error": "Workflow processing failed",
		})
		logger.CountRequest(ctx, "/api/process", 500)
		logger.RecordDuration(ctx, "/api/process", time.Since(start))
		return
	}

	// Simulate processing time
	processingTime := time.Duration(50+rand.Intn(100)) * time.Millisecond
	time.Sleep(processingTime)

	result := map[string]interface{}{
		"ok":          true,
		"workflow_id": req.WorkflowID,
		"status":      "completed",
		"processed_at": time.Now().UTC().Format(time.RFC3339),
		"duration_ms": time.Since(start).Milliseconds(),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(result)

	logger.Info(ctx, "Workflow processed successfully", map[string]interface{}{
		"workflow_id":   req.WorkflowID,
		"duration_ms":   time.Since(start).Milliseconds(),
		"processing_ms": processingTime.Milliseconds(),
	})
	logger.CountRequest(ctx, "/api/process", 200)
	logger.RecordDuration(ctx, "/api/process", time.Since(start))
}

func main() {
	port := getEnvString("PORT", "8000")

	// Create router
	r := mux.NewRouter()

	// Add routes
	r.HandleFunc("/healthz", healthzHandler).Methods("GET")
	r.HandleFunc("/readyz", readyzHandler).Methods("GET")
	r.HandleFunc("/process-user", processUserHandler).Methods("POST")
	
	// Business-level API endpoints for SLI tracking
	r.HandleFunc("/api/users/{id}", getUserHandler).Methods("GET")
	r.HandleFunc("/api/users", createUserHandler).Methods("POST")
	r.HandleFunc("/api/notifications", getNotificationsHandler).Methods("GET")
	r.HandleFunc("/api/process", processWorkflowHandler).Methods("POST")

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
