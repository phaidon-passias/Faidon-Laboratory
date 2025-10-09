import os, random, time, json
from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import logging
from datetime import datetime

app = Flask(__name__)

FAIL_RATE = float(os.getenv("FAIL_RATE", "0.02"))         # 2% default failure rate
READY_DELAY = int(os.getenv("READINESS_DELAY_SEC", "10")) # not ready for N seconds after start
GREETING = os.getenv("GREETING", "hello")
START_TIME = time.time()

REQS = Counter("http_requests_total", "HTTP requests", ["method","endpoint","code"])
LAT = Histogram("http_request_duration_seconds", "Req duration (s)", ["endpoint","method"])

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def log_structured(level, message, **kwargs):
    """Log structured data in JSON format"""
    log_data = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "level": level,
        "message": message,
        "service": "user-service",
        "version": "1.0.0",
        "environment": os.getenv("ENVIRONMENT", "development"),
        **kwargs
    }
    getattr(logger, level.lower())(json.dumps(log_data))

@app.route("/healthz")
def healthz():
    REQS.labels("GET","/healthz","200").inc()
    return "ok", 200

@app.route("/readyz")
def readyz():
    if time.time() - START_TIME < READY_DELAY:
        REQS.labels("GET","/readyz","503").inc()
        return "not ready", 503
    REQS.labels("GET","/readyz","200").inc()
    return "ready", 200

@app.route("/work")
def work():
    """Legacy endpoint for backward compatibility - now acts as user service"""
    t0 = time.time()
    processing_duration = random.uniform(0.05, 0.2)
    
    try:
        # Simulate user data processing
        time.sleep(processing_duration)
        
        if random.random() < FAIL_RATE:
            # Log the failure
            log_structured("ERROR", "User processing failed", 
                         error="simulated user service failure",
                         method=request.method,
                         endpoint="/work",
                         user_agent=request.headers.get('User-Agent', ''),
                         processing_duration_ms=processing_duration * 1000)
            
            REQS.labels("GET", "/work", "500").inc()
            return jsonify({"ok": False, "error": "simulated user service failure"}), 500
        
        # Simulate user data
        user_data = {
            "user_id": f"user_{random.randint(1000, 9999)}",
            "name": f"User {random.randint(1, 100)}",
            "email": f"user{random.randint(1, 100)}@example.com",
            "status": "active",
            "last_login": datetime.utcnow().isoformat() + "Z"
        }
        
        # Log the success
        log_structured("INFO", "User processing completed successfully",
                     method=request.method,
                     endpoint="/work",
                     user_agent=request.headers.get('User-Agent', ''),
                     processing_duration_ms=processing_duration * 1000,
                     user_id=user_data["user_id"],
                     greeting=GREETING)
        
        REQS.labels("GET", "/work", "200").inc()
        return jsonify({"ok": True, "greeting": GREETING, "user_data": user_data}), 200
    finally:
        # Always record latency regardless of success/failure
        LAT.labels("/work", "GET").observe(time.time() - t0)

@app.route("/users/<user_id>")
def get_user(user_id):
    """Get user information by ID"""
    t0 = time.time()
    processing_duration = random.uniform(0.03, 0.15)
    
    try:
        # Simulate user lookup
        time.sleep(processing_duration)
        
        if random.random() < FAIL_RATE:
            # Log the failure
            log_structured("ERROR", "User lookup failed", 
                         error="simulated user lookup failure",
                         method=request.method,
                         endpoint=f"/users/{user_id}",
                         user_id=user_id,
                         user_agent=request.headers.get('User-Agent', ''),
                         processing_duration_ms=processing_duration * 1000)
            
            REQS.labels("GET", f"/users/{user_id}", "500").inc()
            return jsonify({"ok": False, "error": "User lookup failed"}), 500
        
        # Simulate user data
        user_data = {
            "user_id": user_id,
            "name": f"User {user_id}",
            "email": f"user{user_id}@example.com",
            "status": "active",
            "created_at": "2024-01-01T00:00:00Z",
            "last_login": datetime.utcnow().isoformat() + "Z"
        }
        
        # Log the success
        log_structured("INFO", "User lookup completed successfully",
                     method=request.method,
                     endpoint=f"/users/{user_id}",
                     user_id=user_id,
                     user_agent=request.headers.get('User-Agent', ''),
                     processing_duration_ms=processing_duration * 1000)
        
        REQS.labels("GET", f"/users/{user_id}", "200").inc()
        return jsonify({"ok": True, "user": user_data}), 200
    finally:
        # Always record latency regardless of success/failure
        LAT.labels(f"/users/{user_id}", "GET").observe(time.time() - t0)

@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

if __name__ == "__main__":
    # Log startup
    log_structured("INFO", "User service started successfully",
                 port=8000,
                 fail_rate=FAIL_RATE,
                 ready_delay_sec=READY_DELAY,
                 greeting=GREETING,
                 service_type="user-service")
    
    app.run(host="0.0.0.0", port=8000)
