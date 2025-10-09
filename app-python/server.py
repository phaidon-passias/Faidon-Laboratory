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
        "service": "demo-app-python",
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
    t0 = time.time()
    work_duration = random.uniform(0.05, 0.2)
    
    try:
        # Simulate variable latency
        time.sleep(work_duration)
        
        if random.random() < FAIL_RATE:
            # Log the failure
            log_structured("ERROR", "Work request failed", 
                         error="simulated failure",
                         method=request.method,
                         endpoint="/work",
                         user_agent=request.headers.get('User-Agent', ''),
                         work_duration_ms=work_duration * 1000)
            
            REQS.labels("GET", "/work", "500").inc()
            return jsonify({"ok": False, "error": "simulated failure"}), 500
        
        # Log the success
        log_structured("INFO", "Work request completed successfully",
                     method=request.method,
                     endpoint="/work",
                     user_agent=request.headers.get('User-Agent', ''),
                     work_duration_ms=work_duration * 1000,
                     greeting=GREETING)
        
        REQS.labels("GET", "/work", "200").inc()
        return jsonify({"ok": True, "greeting": GREETING}), 200
    finally:
        # Always record latency regardless of success/failure
        LAT.labels("/work", "GET").observe(time.time() - t0)

@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

if __name__ == "__main__":
    # Log startup
    log_structured("INFO", "Application started successfully",
                 port=8000,
                 fail_rate=FAIL_RATE,
                 ready_delay_sec=READY_DELAY,
                 greeting=GREETING)
    
    app.run(host="0.0.0.0", port=8000)
