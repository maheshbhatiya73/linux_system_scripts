#!/bin/bash

set -euo pipefail

# Color codes for output
RESET='\033[0m'
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'

# Health check states
declare -A HEALTH_STATUS
declare -A HEALTH_VALUES
declare -A HEALTH_DETAILS
declare -A HEALTH_THRESHOLDS
declare -a ALERTS
declare -a WARNINGS

# Script variables
SCRIPT_START_TIME=$(date +%s)
VERBOSE_MODE=true
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
CLUSTER_NAME="${CLUSTER_NAME:-}"

# Health metrics
TOTAL_NODES=0
READY_NODES=0
NOT_READY_NODES=0
TOTAL_PODS=0
RUNNING_PODS=0
FAILED_PODS=0
PENDING_PODS=0
UNHEALTHY_PODS=0
OVERALL_HEALTH_SCORE=0

load_telegram_config() {
    local config_file="/etc/system_scripts/auth.conf"
    if [ -f "$config_file" ]; then
        source "$config_file"
        if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ] && 
           [ "$TELEGRAM_BOT_TOKEN" != "your_bot_token" ] && [ "$TELEGRAM_CHAT_ID" != "your_chat_id" ]; then
            return 0
        fi
    fi
    return 1
}

send_telegram_message() {
    local message="$1"
    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    local response=$(curl -s -X POST "$url" -d "chat_id=${TELEGRAM_CHAT_ID}" -d "text=${message}" -d "parse_mode=HTML")
    
    if echo "$response" | grep -q '"ok":true'; then
        return 0
    else
        local error_desc=$(echo "$response" | grep -o '"description":"[^"]*"' | cut -d'"' -f4)
        echo -e "${RED}Telegram Error: ${error_desc}${RESET}" >&2
        return 1
    fi
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed${RESET}"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}Error: Cannot connect to Kubernetes cluster${RESET}"
        exit 1
    fi
}

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║              KUBERNETES HEALTH DIAGNOSTIC                        ║'
    echo '║              Cluster Infrastructure Monitor                      ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${RESET}"
    
    local cluster=$(kubectl config current-context 2>/dev/null || echo "unknown")
    echo -e "${DIM}Started: $(date '+%Y-%m-%d %H:%M:%S') | Cluster: ${cluster}${RESET}"
    echo
}


print_section() {
    local title=$1
    echo -e "\n${CYAN}${BOLD}▌ $title${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────────${RESET}"
}


check_cluster_health() {
    print_section "CLUSTER HEALTH SUMMARY"
    
    # Get API server status
    echo -n "API Server Status: "
    if kubectl get componentstatus 2>/dev/null | grep -q "controller-manager"; then
        echo -e "${GREEN}✓ Operational${RESET}"
        HEALTH_STATUS[api_server]="PASS"
    else
        echo -e "${RED}✗ Not Available${RESET}"
        HEALTH_STATUS[api_server]="FAIL"
        ALERTS+=("API Server is not responding")
    fi

    # Check cluster version
    echo -n "API Version: "
    local version=$(kubectl version --short 2>/dev/null | grep "Server Version" | awk '{print $3}')
    echo -e "${GREEN}$version${RESET}"

    # Check component status
    echo -n "Control Plane Components: "
    local cs_status=$(kubectl get componentstatus 2>/dev/null | tail -n +2 | grep -c "Healthy")
    local cs_total=$(kubectl get componentstatus 2>/dev/null | tail -n +2 | wc -l)
    
    if [ "$cs_status" -eq "$cs_total" ]; then
        echo -e "${GREEN}✓ All Healthy (${cs_status}/${cs_total})${RESET}"
        HEALTH_STATUS[control_plane]="PASS"
    else
        echo -e "${YELLOW}⚠ ${cs_status}/${cs_total} Healthy${RESET}"
        HEALTH_STATUS[control_plane]="WARN"
        WARNINGS+=("Some control plane components are not healthy: ${cs_status}/${cs_total}")
    fi

    # Check cluster resources
    echo -n "Cluster Resources: "
    local node_allocatable=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    echo -e "${GREEN}${node_allocatable} nodes available${RESET}"

    HEALTH_STATUS[cluster]="PASS"
    HEALTH_DETAILS[cluster]="Cluster is operational with ${node_allocatable} nodes"
}

check_node_health() {
    print_section "NODE HEALTH CHECKER"
    
    TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo 0)
    NOT_READY_NODES=$((TOTAL_NODES - READY_NODES))
    
    echo -e "${BOLD}Node Status Summary:${RESET}"
    echo "  Total Nodes: ${GREEN}${TOTAL_NODES}${RESET}"
    echo "  Ready Nodes: ${GREEN}${READY_NODES}${RESET}"
    echo "  Not Ready: $([ $NOT_READY_NODES -gt 0 ] && echo -e "${RED}${NOT_READY_NODES}${RESET}" || echo -e "${GREEN}0${RESET}")"
    
    # Detailed node status
    echo -e "\n${BOLD}Detailed Node Status:${RESET}"
    local node_info=$(kubectl get nodes -o wide 2>/dev/null)
    echo "$node_info" | head -1
    
    while IFS= read -r line; do
        local node_name=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $2}')
        local cpu=$(echo "$line" | awk '{print $3}')
        local memory=$(echo "$line" | awk '{print $4}')
        
        if [[ "$status" == "Ready" ]]; then
            echo -e "  ${GREEN}✓${RESET} $node_name | Status: ${GREEN}Ready${RESET} | CPU: $cpu | Memory: $memory"
        else
            echo -e "  ${RED}✗${RESET} $node_name | Status: ${RED}${status}${RESET} | CPU: $cpu | Memory: $memory"
            ALERTS+=("Node $node_name is not ready (Status: $status)")
        fi
    done < <(echo "$node_info" | tail -n +2)
    
    # Set node health status
    if [ $NOT_READY_NODES -eq 0 ]; then
        HEALTH_STATUS[nodes]="PASS"
    elif [ $NOT_READY_NODES -lt $TOTAL_NODES ]; then
        HEALTH_STATUS[nodes]="WARN"
        WARNINGS+=("${NOT_READY_NODES} node(s) not ready")
    else
        HEALTH_STATUS[nodes]="FAIL"
        ALERTS+=("All nodes are not ready!")
    fi
}

check_pod_health() {
    print_section "POD HEALTH CHECKER"
    
    echo -e "${BOLD}Pod Status Summary (All Namespaces):${RESET}"
    
    RUNNING_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    PENDING_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
    FAILED_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
    TOTAL_PODS=$((RUNNING_PODS + PENDING_PODS + FAILED_PODS))
    
    echo "  Total Pods: ${GREEN}${TOTAL_PODS}${RESET}"
    echo "  Running: ${GREEN}${RUNNING_PODS}${RESET}"
    echo "  Pending: $([ $PENDING_PODS -gt 0 ] && echo -e "${YELLOW}${PENDING_PODS}${RESET}" || echo -e "${GREEN}0${RESET}")"
    echo "  Failed: $([ $FAILED_PODS -gt 0 ] && echo -e "${RED}${FAILED_PODS}${RESET}" || echo -e "${GREEN}0${RESET}")"
    
    # Check for unhealthy pods
    echo -e "\n${BOLD}Unhealthy Pods:${RESET}"
    local unhealthy=$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running --no-headers 2>/dev/null)
    
    if [ -z "$unhealthy" ]; then
        echo -e "  ${GREEN}✓ All pods are healthy${RESET}"
        UNHEALTHY_PODS=0
        HEALTH_STATUS[pods]="PASS"
    else
        UNHEALTHY_PODS=$(echo "$unhealthy" | wc -l)
        echo -e "  ${YELLOW}⚠ ${UNHEALTHY_PODS} unhealthy pod(s) detected${RESET}"
        echo "$unhealthy" | while read -r line; do
            local ns=$(echo "$line" | awk '{print $1}')
            local pod=$(echo "$line" | awk '{print $2}')
            local status=$(echo "$line" | awk '{print $3}')
            echo -e "    ${YELLOW}•${RESET} $ns/$pod - Status: $status"
            WARNINGS+=("Pod $ns/$pod has status: $status")
        done
        HEALTH_STATUS[pods]="WARN"
    fi
    
    # Check pod restart count
    echo -e "\n${BOLD}Pod Restart Analysis:${RESET}"
    local high_restart_pods=$(kubectl get pods --all-namespaces --sort-by='.status.containerStatuses[0].restartCount' 2>/dev/null | tail -5)
    
    if [ -n "$high_restart_pods" ]; then
        echo "$high_restart_pods" | tail -n +2 | while read -r line; do
            local ns=$(echo "$line" | awk '{print $1}')
            local pod=$(echo "$line" | awk '{print $2}')
            local restarts=$(echo "$line" | awk '{print $4}')
            
            if [ "$restarts" -gt 5 ]; then
                echo -e "    ${RED}✗${RESET} $ns/$pod - Restarts: ${RED}${restarts}${RESET}"
                ALERTS+=("Pod $ns/$pod has high restart count: $restarts")
            fi
        done
    fi
}

check_namespace_health() {
    print_section "NAMESPACE HEALTH ANALYSIS"
    
    echo -e "${BOLD}Namespace Overview:${RESET}"
    local ns_info=$(kubectl get ns 2>/dev/null)
    echo "$ns_info" | head -1
    
    kubectl get ns --no-headers 2>/dev/null | while read -r line; do
        local ns=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $2}')
        local pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
        
        echo -e "  ${GREEN}✓${RESET} $ns | Status: $status | Pods: $pod_count"
    done
}

check_resource_usage() {
    print_section "CLUSTER RESOURCE USAGE"
    
    echo -e "${BOLD}Node Resource Metrics:${RESET}"
    
    # Check if metrics-server is available
    if kubectl get deployment metrics-server -n kube-system &>/dev/null 2>&1; then
        echo "  Metrics Server: ${GREEN}✓ Available${RESET}"
        
        # Get top nodes
        echo -e "\n${BOLD}Top CPU/Memory Usage by Node:${RESET}"
        local node_metrics=$(kubectl top nodes 2>/dev/null || echo "")
        
        if [ -n "$node_metrics" ]; then
            echo "$node_metrics" | head -1
            kubectl top nodes 2>/dev/null | tail -n +2 | while read -r line; do
                local node=$(echo "$line" | awk '{print $1}')
                local cpu=$(echo "$line" | awk '{print $2}')
                local mem=$(echo "$line" | awk '{print $3}')
                
                echo -e "  $node | CPU: ${GREEN}${cpu}${RESET} | Memory: ${GREEN}${mem}${RESET}"
            done
        fi
    else
        echo "  Metrics Server: ${YELLOW}⚠ Not installed${RESET}"
        WARNINGS+=("Metrics server not found - Install with: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml")
    fi
}

print_alerts() {
    print_section "ALERTS & WARNINGS"
    
    local alert_count=${#ALERTS[@]}
    local warning_count=${#WARNINGS[@]}
    
    if [ $alert_count -gt 0 ]; then
        echo -e "${BG_RED}${WHITE}${BOLD} CRITICAL ALERTS (${alert_count}) ${RESET}"
        for alert in "${ALERTS[@]}"; do
            echo -e "  ${RED}✗${RESET} $alert"
        done
        echo
    fi
    
    if [ $warning_count -gt 0 ]; then
        echo -e "${BG_YELLOW}${BLACK}${BOLD} WARNINGS (${warning_count}) ${RESET}"
        for warning in "${WARNINGS[@]}"; do
            echo -e "  ${YELLOW}⚠${RESET} $warning"
        done
        echo
    fi
    
    if [ $alert_count -eq 0 ] && [ $warning_count -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ NO ALERTS OR WARNINGS${RESET}"
        echo -e "  ${GREEN}Kubernetes cluster is operating normally${RESET}"
    fi
}

calculate_health_score() {
    local total=0
    local score=0
    
    # Node health (40 points)
    if [ "$HEALTH_STATUS[nodes]" = "PASS" ]; then
        score=$((score + 40))
    elif [ "$HEALTH_STATUS[nodes]" = "WARN" ]; then
        score=$((score + 20))
    fi
    total=$((total + 40))
    
    # Pod health (40 points)
    if [ "$HEALTH_STATUS[pods]" = "PASS" ]; then
        score=$((score + 40))
    elif [ "$HEALTH_STATUS[pods]" = "WARN" ]; then
        score=$((score + 20))
    fi
    total=$((total + 40))
    
    # Cluster health (20 points)
    if [ "$HEALTH_STATUS[cluster]" = "PASS" ]; then
        score=$((score + 20))
    fi
    total=$((total + 20))
    
    OVERALL_HEALTH_SCORE=$((score * 100 / total))
}

print_summary() {
    calculate_health_score
    
    print_section "HEALTH REPORT SUMMARY"
    
    # Overall status
    local overall_status="HEALTHY"
    local status_color=$GREEN
    
    if [ ${#ALERTS[@]} -gt 0 ]; then
        overall_status="CRITICAL"
        status_color=$RED
    elif [ ${#WARNINGS[@]} -gt 0 ]; then
        overall_status="WARNING"
        status_color=$YELLOW
    fi
    
    echo -e "${BOLD}Overall Status:${RESET} ${status_color}${overall_status}${RESET}"
    echo -e "${BOLD}Health Score:${RESET} ${GREEN}${OVERALL_HEALTH_SCORE}/100${RESET}"
    
    echo -e "\n${BOLD}Cluster Statistics:${RESET}"
    echo "  Nodes: ${GREEN}${READY_NODES}/${TOTAL_NODES}${RESET} ready"
    echo "  Pods: ${GREEN}${RUNNING_PODS}/${TOTAL_PODS}${RESET} running"
    echo "  Alerts: $([ ${#ALERTS[@]} -gt 0 ] && echo -e "${RED}${#ALERTS[@]}${RESET}" || echo -e "${GREEN}0${RESET}")"
    echo "  Warnings: $([ ${#WARNINGS[@]} -gt 0 ] && echo -e "${YELLOW}${#WARNINGS[@]}${RESET}" || echo -e "${GREEN}0${RESET}")"
    
    echo -e "\n${DIM}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${DIM}Report Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
    echo -e "${DIM}Cluster: $(kubectl config current-context 2>/dev/null || echo "unknown")${RESET}"
    echo -e "${DIM}═══════════════════════════════════════════════════════════════${RESET}\n"
}

send_telegram_report() {
    if ! load_telegram_config; then
        echo -e "\n${YELLOW}⚠ Telegram configuration not found. Skipping Telegram notification.${RESET}"
        echo -e "${DIM}To enable Telegram notifications, create /etc/system_scripts/auth.conf with:${RESET}"
        echo -e "${DIM}  TELEGRAM_BOT_TOKEN=\"your_bot_token\"${RESET}"
        echo -e "${DIM}  TELEGRAM_CHAT_ID=\"your_chat_id\"${RESET}"
        return
    fi
    
    echo -e "\n${CYAN}Sending report to Telegram...${RESET}"
    
    # Determine status emoji
    local status_emoji="✅"
    local status_text="HEALTHY"
    
    if [ ${#ALERTS[@]} -gt 0 ]; then
        status_emoji="🚨"
        status_text="CRITICAL"
    elif [ ${#WARNINGS[@]} -gt 0 ]; then
        status_emoji="⚠️"
        status_text="WARNING"
    fi
    
    # Build message
    local message="<b>${status_emoji} Kubernetes Health Report</b>%0A"
    message+="<b>Status:</b> ${status_text}%0A"
    message+="<b>Score:</b> ${OVERALL_HEALTH_SCORE}/100%0A"
    message+="<b>Cluster:</b> $(kubectl config current-context 2>/dev/null || echo 'unknown')%0A%0A"
    
    message+="<b>Nodes:</b> ${READY_NODES}/${TOTAL_NODES} Ready%0A"
    message+="<b>Pods:</b> ${RUNNING_PODS}/${TOTAL_PODS} Running%0A%0A"
    
    if [ ${#ALERTS[@]} -gt 0 ]; then
        message+="<b>🚨 ALERTS (${#ALERTS[@]}):</b>%0A"
        for alert in "${ALERTS[@]}"; do
            message+="• ${alert}%0A"
        done
        message+="%0A"
    fi
    
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        message+="<b>⚠️ WARNINGS (${#WARNINGS[@]}):</b>%0A"
        for warning in "${WARNINGS[@]}"; do
            message+="• ${warning}%0A"
        done
        message+="%0A"
    fi
    
    message+="<b>Time:</b> $(date '+%Y-%m-%d %H:%M:%S %Z')"
    
    if send_telegram_message "$message"; then
        echo -e "${GREEN}Report sent to Telegram successfully!${RESET}"
    else
        echo -e "${RED}Failed to send report to Telegram. Check bot token and chat ID.${RESET}"
    fi
}

main() {
    print_header
    
    # Check prerequisites
    echo -e "${CYAN}Checking prerequisites...${RESET}"
    check_kubectl
    echo -e "${GREEN}✓ kubectl is available${RESET}\n"
    
    # Run all health checks
    check_cluster_health
    check_node_health
    check_pod_health
    check_namespace_health
    check_resource_usage
    print_alerts
    print_summary
    
    # Send Telegram report
    send_telegram_report
    
    # Set exit code based on health status
    if [ ${#ALERTS[@]} -gt 0 ]; then
        exit 1
    elif [ ${#WARNINGS[@]} -gt 0 ]; then
        exit 2
    else
        exit 0
    fi
}

# Run main function
main "$@"
