#!/usr/bin/env bash
set -euo pipefail

# HPA Demo Script - Load testing with Horizontal Pod Autoscaler
# Usage: ./hpa-demo.sh [run|watch|reset]

usage() {
  cat <<EOF
Usage: $(basename "$0") [run|watch|reset]

Commands:
  run         Standard load test to trigger HPA scaling
  watch       Monitor HPA scaling without load testing
  reset       Reset deployment to clean state (2 replicas)

Environment overrides:
  HPA_CONCURRENCY   Default: 200
  HPA_DURATION      Default: 60
  HPA_NAMESPACE     Default: dev

Examples:
  ./scripts/hpa-demo.sh reset       # Reset to clean state
  ./scripts/hpa-demo.sh run         # Run load test
  ./scripts/hpa-demo.sh watch       # Monitor HPA scaling
  HPA_CONCURRENCY=300 ./scripts/hpa-demo.sh run  # Custom concurrency
EOF
}

# Default values
HPA_CONCURRENCY=${HPA_CONCURRENCY:-200}
HPA_DURATION=${HPA_DURATION:-60}
HPA_NAMESPACE=${HPA_NAMESPACE:-dev}

monitor_loop() {
  local duration=${1:-60}
  local iterations=$((duration / 5))
  
  for _ in $(seq 1 $iterations); do
    echo "--- $(date) ---"
    echo "🔥 HPA Status:"
    kubectl -n $HPA_NAMESPACE get hpa -o wide | cat || true
    echo ""
    echo "📊 Deployment Status:"
    kubectl -n $HPA_NAMESPACE get deploy/app -o wide | cat || true
    echo ""
    echo "🚀 Pod Status:"
    kubectl -n $HPA_NAMESPACE get pods -o wide | cat || true
    echo ""
    sleep 5
  done
}

# Standard load test for HPA
run_load_test() {
  echo "🚀 Starting HPA load test..."
  echo "   Concurrency: ${HPA_CONCURRENCY}"
  echo "   Duration: ${HPA_DURATION}s"
  echo "   Namespace: ${HPA_NAMESPACE}"
  
  # Start port-forward
  kubectl -n $HPA_NAMESPACE port-forward svc/app 8080:80 >/tmp/pf-app.log 2>&1 & echo $! > /tmp/pf-app.pid
  cleanup() { 
    if [ -f /tmp/pf-app.pid ]; then
      kill $(cat /tmp/pf-app.pid) >/dev/null 2>&1 || true
      rm -f /tmp/pf-app.pid
    fi
  }
  trap cleanup EXIT INT TERM
  
  # Wait for app readiness (reduced wait time)
  echo "Waiting for app readiness..."
  for i in $(seq 1 10); do
    if curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then 
      echo "App is ready."
      break
    fi
    sleep 1
  done
  
  # Start monitoring in background
  monitor_loop $HPA_DURATION &
  MONITOR_PID=$!
  
  # Run load test
  echo "Running hey load test..."
  if command -v hey >/dev/null 2>&1; then
    hey -z ${HPA_DURATION}s -c $HPA_CONCURRENCY http://localhost:8080/work 2>/dev/null
  else
    echo "hey not found, using curl fallback..."
    for i in $(seq 1 $((HPA_CONCURRENCY * HPA_DURATION / 10))); do
      curl -sf http://localhost:8080/work >/dev/null 2>&1 &
      sleep 0.1
    done
    wait
  fi
  
  # Wait for monitoring to complete
  wait $MONITOR_PID 2>/dev/null || true
  
  echo "🔥 HPA load test completed!"
}

# Reset deployment to clean state
reset_deployment() {
  echo "🔄 Resetting deployment to clean state..."
  
  # Scale deployment to 2 replicas (minimum for HPA)
  kubectl -n $HPA_NAMESPACE scale deployment app --replicas=2
  
  # Wait for pods to be ready
  echo "Waiting for pods to be ready..."
  kubectl -n $HPA_NAMESPACE wait --for=condition=ready pod -l app.kubernetes.io/name=app --timeout=60s
  
  # Show current status
  echo "📊 Current Status:"
  echo "🔥 HPA Status:"
  kubectl -n $HPA_NAMESPACE get hpa -o wide | cat || true
  echo ""
  echo "📊 Deployment Status:"
  kubectl -n $HPA_NAMESPACE get deploy/app -o wide | cat || true
  echo ""
  echo "🚀 Pod Status:"
  kubectl -n $HPA_NAMESPACE get pods -o wide | cat || true
  
  echo "✅ Deployment reset complete!"
}

# Main script logic
case "${1:-run}" in
  run)
    run_load_test
    ;;
  watch)
    echo "👀 Monitoring HPA scaling..."
    monitor_loop 300  # Monitor for 5 minutes
    ;;
  reset)
    reset_deployment
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $1"
    usage
    exit 1
    ;;
esac