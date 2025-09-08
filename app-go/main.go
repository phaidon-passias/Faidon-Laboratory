package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Configuration from environment variables
var (
	failRate    float64
	readyDelay  int
	greeting    string
	startTime   time.Time
)

// Prometheus metrics
var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "HTTP requests",
		},
		[]string{"method", "endpoint", "code"},
	)
	
	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name: "http_request_duration_seconds",
			Help: "Request duration in seconds",
		},
		[]string{"endpoint", "method"},
	)
)

func init() {
	// Register Prometheus metrics
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
	
	// Initialize configuration from environment variables
	failRate = getEnvFloat("FAIL_RATE", 0.02)
	readyDelay = getEnvInt("READINESS_DELAY_SEC", 10)
	greeting = getEnvString("GREETING", "hello")
	startTime = time.Now()
	
	// Seed random number generator
	rand.Seed(time.Now().UnixNano())
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
	httpRequestsTotal.WithLabelValues("GET", "/healthz", "200").Inc()
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

// Readiness endpoint
func readyzHandler(w http.ResponseWriter, r *http.Request) {
	elapsed := time.Since(startTime)
	if elapsed < time.Duration(readyDelay)*time.Second {
		httpRequestsTotal.WithLabelValues("GET", "/readyz", "503").Inc()
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte("not ready"))
		return
	}
	
	httpRequestsTotal.WithLabelValues("GET", "/readyz", "200").Inc()
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ready"))
}

// Work endpoint with configurable failure rate and latency
func workHandler(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	
	// Simulate variable latency (50-200ms)
	latency := time.Duration(50+rand.Intn(150)) * time.Millisecond
	time.Sleep(latency)
	
	// Check for simulated failure
	if rand.Float64() < failRate {
		httpRequestsTotal.WithLabelValues("GET", "/work", "500").Inc()
		httpRequestDuration.WithLabelValues("/work", "GET").Observe(time.Since(start).Seconds())
		
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":    false,
			"error": "simulated failure",
		})
		return
	}
	
	// Success response
	httpRequestsTotal.WithLabelValues("GET", "/work", "200").Inc()
	httpRequestDuration.WithLabelValues("/work", "GET").Observe(time.Since(start).Seconds())
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"ok":       true,
		"greeting": greeting,
	})
}

// Metrics endpoint
func metricsHandler(w http.ResponseWriter, r *http.Request) {
	promhttp.Handler().ServeHTTP(w, r)
}

func main() {
	// Create router
	r := mux.NewRouter()
	
	// Register routes
	r.HandleFunc("/healthz", healthzHandler).Methods("GET")
	r.HandleFunc("/readyz", readyzHandler).Methods("GET")
	r.HandleFunc("/work", workHandler).Methods("GET")
	r.HandleFunc("/metrics", metricsHandler).Methods("GET")
	
	// Start server
	port := getEnvString("PORT", "8000")
	log.Printf("Starting server on port %s", port)
	log.Printf("Configuration: failRate=%.2f, readyDelay=%ds, greeting=%s", failRate, readyDelay, greeting)
	
	if err := http.ListenAndServe(fmt.Sprintf(":%s", port), r); err != nil {
		log.Fatal("Server failed to start:", err)
	}
}
