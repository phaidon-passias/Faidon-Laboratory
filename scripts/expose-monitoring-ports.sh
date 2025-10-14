#!/usr/bin/env bash
set -euo pipefail

# Script to expose monitoring stack ports for local access
# This will port-forward Grafana, Tempo, Loki, and other monitoring services

NAMESPACE="monitoring"
PIDS_FILE="/tmp/monitoring-port-forwards.pids"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Monitoring Stack Port Forwarding${NC}"
echo "=================================="

# Function to start port forwarding
start_port_forward() {
    local service_name="$1"
    local local_port="$2"
    local remote_port="$3"
    local description="$4"
    
    echo -e "${YELLOW}Starting port forward: ${service_name}${NC}"
    echo -e "  Local:  http://localhost:${local_port}"
    echo -e "  Remote: ${service_name}:${remote_port}"
    echo -e "  Desc:   ${description}"
    
    kubectl port-forward -n "${NAMESPACE}" "service/${service_name}" "${local_port}:${remote_port}" > /dev/null 2>&1 &
    local pid=$!
    echo "${pid}" >> "${PIDS_FILE}"
    echo -e "${GREEN}✓ Started (PID: ${pid})${NC}"
    echo ""
}

# Function to stop all port forwards
stop_all_forwards() {
    if [[ -f "${PIDS_FILE}" ]]; then
        echo -e "${YELLOW}Stopping all port forwards...${NC}"
        while read -r pid; do
            if kill -0 "${pid}" 2>/dev/null; then
                kill "${pid}"
                echo -e "${GREEN}✓ Stopped PID: ${pid}${NC}"
            fi
        done < "${PIDS_FILE}"
        rm -f "${PIDS_FILE}"
        echo -e "${GREEN}All port forwards stopped.${NC}"
    else
        echo -e "${YELLOW}No active port forwards found.${NC}"
    fi
}

# Function to check if services exist
check_service() {
    local service_name="$1"
    if kubectl get service -n "${NAMESPACE}" "${service_name}" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to show status
show_status() {
    echo -e "${BLUE}📊 Current Port Forward Status${NC}"
    echo "=============================="
    
    if [[ -f "${PIDS_FILE}" ]]; then
        while read -r pid; do
            if kill -0 "${pid}" 2>/dev/null; then
                echo -e "${GREEN}✓ PID ${pid} is running${NC}"
            else
                echo -e "${RED}✗ PID ${pid} is not running${NC}"
            fi
        done < "${PIDS_FILE}"
    else
        echo -e "${YELLOW}No port forwards active${NC}"
    fi
    echo ""
}

# Function to show available services
show_services() {
    echo -e "${BLUE}🔍 Available Monitoring Services${NC}"
    echo "=================================="
    kubectl get services -n "${NAMESPACE}" -o custom-columns="NAME:.metadata.name,PORT:.spec.ports[0].port,TYPE:.spec.type" 2>/dev/null || echo "No services found in ${NAMESPACE} namespace"
    echo ""
}

# Main logic
case "${1:-start}" in
    "start")
        echo -e "${YELLOW}Starting monitoring stack port forwards...${NC}"
        echo ""
        
        # Clear any existing PIDs file
        rm -f "${PIDS_FILE}"
        
        # Grafana UI
        if check_service "lgtm-stack-grafana"; then
            start_port_forward "lgtm-stack-grafana" "3000" "80" "Grafana Dashboard"
        else
            echo -e "${RED}✗ Grafana service not found${NC}"
        fi
        
        # Note: Other services (Tempo, Loki, Mimir, Alloy) can be accessed through Grafana
        # or added back to this script if needed for direct access
        
        echo -e "${GREEN}🎉 Port forwarding started!${NC}"
        echo ""
        echo -e "${BLUE}📋 Access URLs:${NC}"
        echo "  Grafana:      http://localhost:3000 (admin/prom-operator)"
        echo ""
        echo -e "${YELLOW}💡 Other services (Tempo, Loki, Mimir) can be accessed through Grafana${NC}"
        echo ""
        echo -e "${YELLOW}💡 Use '${0} stop' to stop all port forwards${NC}"
        echo -e "${YELLOW}💡 Use '${0} status' to check status${NC}"
        ;;
        
    "stop")
        stop_all_forwards
        ;;
        
    "status")
        show_status
        ;;
        
    "services")
        show_services
        ;;
        
    "restart")
        stop_all_forwards
        sleep 2
        "${0}" start
        ;;
        
    *)
        echo -e "${BLUE}Usage: ${0} {start|stop|status|services|restart}${NC}"
        echo ""
        echo "Commands:"
        echo "  start    - Start port forwarding for all monitoring services"
        echo "  stop     - Stop all active port forwards"
        echo "  status   - Show status of active port forwards"
        echo "  services - List available monitoring services"
        echo "  restart  - Stop and restart all port forwards"
        echo ""
        echo "Default action is 'start'"
        exit 1
        ;;
esac
