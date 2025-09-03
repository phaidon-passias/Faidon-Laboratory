#!/usr/bin/env bash
set -euo pipefail

# Simple HPA demo helper
# - Starts load via make hpa-load with optional overrides
# - Shows a concise HPA/Deployment/Pods view for ~60s
# - Or runs an interactive HPA watch

usage() {
  cat <<EOF
Usage: $(basename "$0") [run|watch]

Commands:
  run    Start load (make hpa-load) and print HPA/deploy/pods snapshot loop
  watch  Run 'make hpa-watch' to stream HPA updates

Environment overrides (for 'run'):
  HPA_CONCURRENCY   Default: 200
  HPA_DURATION      Default: 60 (seconds)
  HPA_PAUSE         Default: 0.1 (seconds, curl fallback only)

Examples:
  HPA_CONCURRENCY=200 HPA_DURATION=60 ./hpa-demo.sh run
  ./hpa-demo.sh watch
EOF
}

monitor_loop() {
  for _ in {1..12}; do
    echo "--- $(date) ---"
    kubectl -n app get hpa | cat || true
    kubectl -n app get deploy/app | cat || true
    kubectl -n app get pods | cat || true
    sleep 5
  done
}

cmd="${1:-run}"
case "$cmd" in
  run)
    # Defaults if not set
    export HPA_CONCURRENCY="${HPA_CONCURRENCY:-200}"
    export HPA_DURATION="${HPA_DURATION:-60}"
    export HPA_PAUSE="${HPA_PAUSE:-0.1}"

    # Start load in the background
    echo "Starting load: HPA_CONCURRENCY=${HPA_CONCURRENCY} HPA_DURATION=${HPA_DURATION}"
    ( HPA_CONCURRENCY="${HPA_CONCURRENCY}" HPA_DURATION="${HPA_DURATION}" HPA_PAUSE="${HPA_PAUSE}" make hpa-load | cat ) &
    load_pid=$!

    # Show state for ~60s
    monitor_loop

    # Ensure background finishes (best-effort)
    wait ${load_pid} 2>/dev/null || true
    ;;
  watch)
    make hpa-watch | cat
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac


