import os
import random
import time
from flask import Flask, jsonify, request
from faidon_laboratory_logging import Logger, Config

app = Flask(__name__)

# Configuration from environment variables
FAIL_RATE = float(os.getenv("FAIL_RATE", "0.02"))
READY_DELAY = int(os.getenv("READINESS_DELAY_SEC", "10"))
GREETING = os.getenv("GREETING", "hello")
START_TIME = time.time()

# Initialize logger
logger = Logger(Config(
    service_name=os.getenv("SERVICE_NAME", "user-service"),
    version=os.getenv("SERVICE_VERSION", "1.0.0"),
    environment=os.getenv("ENVIRONMENT", "development"),
    alloy_url=os.getenv("ALLOY_URL", "grafana-alloy.monitoring.svc.cluster.local:4318")
))

@app.route("/healthz")
def healthz():
    with logger.start_span("healthz") as span:
        logger.info("Health check requested")
        logger.count_request("/healthz", 200)
        return "ok", 200

@app.route("/readyz")
def readyz():
    with logger.start_span("readyz") as span:
        elapsed = time.time() - START_TIME
        if elapsed < READY_DELAY:
            logger.warn("Service not ready yet", 
                       elapsed_seconds=elapsed, 
                       ready_delay_seconds=READY_DELAY)
            logger.count_request("/readyz", 503)
            return "not ready", 503
        
        logger.info("Service is ready")
        logger.count_request("/readyz", 200)
        return "ready", 200

@app.route("/work")
def work():
    """Legacy endpoint for backward compatibility - now acts as user service"""
    with logger.start_span("work") as span:
        start_time = time.time()
        processing_duration = random.uniform(0.05, 0.2)
        
        try:
            # Simulate user data processing
            time.sleep(processing_duration)
            
            if random.random() < FAIL_RATE:
                logger.error("User processing failed", 
                           Exception("simulated user service failure"),
                           method=request.method,
                           endpoint="/work",
                           user_agent=request.headers.get('User-Agent', ''),
                           processing_duration_ms=processing_duration * 1000)
                
                logger.count_request("/work", 500)
                return jsonify({"ok": False, "error": "simulated user service failure"}), 500
            
            # Simulate user data
            user_data = {
                "user_id": f"user_{random.randint(1000, 9999)}",
                "name": f"User {random.randint(1, 100)}",
                "email": f"user{random.randint(1, 100)}@example.com",
                "status": "active",
                "last_login": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            }
            
            logger.info("User processing completed successfully",
                       method=request.method,
                       endpoint="/work",
                       user_agent=request.headers.get('User-Agent', ''),
                       processing_duration_ms=processing_duration * 1000,
                       user_id=user_data["user_id"],
                       greeting=GREETING)
            
            logger.count_request("/work", 200)
            return jsonify({"ok": True, "greeting": GREETING, "user_data": user_data}), 200
            
        except Exception as e:
            logger.error("Unexpected error in work endpoint", e)
            logger.count_request("/work", 500)
            return jsonify({"ok": False, "error": "Internal server error"}), 500

@app.route("/users/<user_id>")
def get_user(user_id):
    """Get user information by ID"""
    with logger.start_span("get_user") as span:
        start_time = time.time()
        processing_duration = random.uniform(0.03, 0.15)
        
        try:
            # Simulate user lookup
            time.sleep(processing_duration)
            
            if random.random() < FAIL_RATE:
                logger.error("User lookup failed", 
                           Exception("simulated user lookup failure"),
                           method=request.method,
                           endpoint=f"/users/{user_id}",
                           user_id=user_id,
                           user_agent=request.headers.get('User-Agent', ''),
                           processing_duration_ms=processing_duration * 1000)
                
                logger.count_request(f"/users/{user_id}", 500)
                return jsonify({"ok": False, "error": "User lookup failed"}), 500
            
            # Simulate user data
            user_data = {
                "user_id": user_id,
                "name": f"User {user_id}",
                "email": f"user{user_id}@example.com",
                "status": "active",
                "created_at": "2024-01-01T00:00:00Z",
                "last_login": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            }
            
            logger.info("User lookup completed successfully",
                       method=request.method,
                       endpoint=f"/users/{user_id}",
                       user_id=user_id,
                       user_agent=request.headers.get('User-Agent', ''),
                       processing_duration_ms=processing_duration * 1000)
            
            logger.count_request(f"/users/{user_id}", 200)
            return jsonify({"ok": True, "user": user_data}), 200
            
        except Exception as e:
            logger.error("Unexpected error in get_user endpoint", e, user_id=user_id)
            logger.count_request(f"/users/{user_id}", 500)
            return jsonify({"ok": False, "error": "Internal server error"}), 500

@app.route("/users", methods=["POST"])
def create_user():
    """Create a new user"""
    with logger.start_span("create_user") as span:
        start_time = time.time()
        processing_duration = random.uniform(0.1, 0.3)
        
        try:
            # Get request data
            data = request.get_json()
            if not data or 'name' not in data or 'email' not in data:
                logger.warn("Invalid user creation request", 
                           method=request.method,
                           endpoint="/users",
                           user_agent=request.headers.get('User-Agent', ''))
                logger.count_request("/users", 400)
                return jsonify({"ok": False, "error": "Name and email are required"}), 400
            
            # Simulate user creation processing
            time.sleep(processing_duration)
            
            if random.random() < FAIL_RATE:
                logger.error("User creation failed", 
                           Exception("simulated user creation failure"),
                           method=request.method,
                           endpoint="/users",
                           name=data.get('name'),
                           email=data.get('email'),
                           user_agent=request.headers.get('User-Agent', ''),
                           processing_duration_ms=processing_duration * 1000)
                
                logger.count_request("/users", 500)
                return jsonify({"ok": False, "error": "User creation failed"}), 500
            
            # Generate user ID
            user_id = f"user_{random.randint(1000, 9999)}"
            
            # Simulate user data
            user_data = {
                "user_id": user_id,
                "name": data['name'],
                "email": data['email'],
                "status": "active",
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "last_login": None
            }
            
            logger.info("User created successfully",
                       method=request.method,
                       endpoint="/users",
                       user_id=user_id,
                       name=data['name'],
                       email=data['email'],
                       user_agent=request.headers.get('User-Agent', ''),
                       processing_duration_ms=processing_duration * 1000)
            
            logger.count_request("/users", 201)
            return jsonify({"ok": True, "user": user_data}), 201
            
        except Exception as e:
            logger.error("Unexpected error in create_user endpoint", e)
            logger.count_request("/users", 500)
            return jsonify({"ok": False, "error": "Internal server error"}), 500

@app.route("/users/<user_id>/profile")
def get_user_profile(user_id):
    """Get extended user profile data"""
    with logger.start_span("get_user_profile") as span:
        start_time = time.time()
        processing_duration = random.uniform(0.05, 0.15)
        
        try:
            # Simulate profile lookup
            time.sleep(processing_duration)
            
            if random.random() < FAIL_RATE:
                logger.error("User profile lookup failed", 
                           Exception("simulated profile lookup failure"),
                           method=request.method,
                           endpoint=f"/users/{user_id}/profile",
                           user_id=user_id,
                           user_agent=request.headers.get('User-Agent', ''),
                           processing_duration_ms=processing_duration * 1000)
                
                logger.count_request(f"/users/{user_id}/profile", 500)
                return jsonify({"ok": False, "error": "Profile lookup failed"}), 500
            
            # Simulate extended user profile data
            profile_data = {
                "user_id": user_id,
                "name": f"User {user_id}",
                "email": f"user{user_id}@example.com",
                "status": "active",
                "created_at": "2024-01-01T00:00:00Z",
                "last_login": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "profile": {
                    "bio": f"This is the profile for user {user_id}",
                    "location": "San Francisco, CA",
                    "website": f"https://example.com/users/{user_id}",
                    "preferences": {
                        "theme": "dark",
                        "notifications": True,
                        "language": "en"
                    },
                    "stats": {
                        "posts": random.randint(10, 100),
                        "followers": random.randint(50, 500),
                        "following": random.randint(20, 200)
                    }
                }
            }
            
            logger.info("User profile retrieved successfully",
                       method=request.method,
                       endpoint=f"/users/{user_id}/profile",
                       user_id=user_id,
                       user_agent=request.headers.get('User-Agent', ''),
                       processing_duration_ms=processing_duration * 1000)
            
            logger.count_request(f"/users/{user_id}/profile", 200)
            return jsonify({"ok": True, "profile": profile_data}), 200
            
        except Exception as e:
            logger.error("Unexpected error in get_user_profile endpoint", e, user_id=user_id)
            logger.count_request(f"/users/{user_id}/profile", 500)
            return jsonify({"ok": False, "error": "Internal server error"}), 500

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8000"))
    
    # Log startup
    logger.info("User service started successfully",
               port=port,
               fail_rate=FAIL_RATE,
               ready_delay_sec=READY_DELAY,
               greeting=GREETING,
               service_type="user-service")
    
    app.run(host="0.0.0.0", port=port)
