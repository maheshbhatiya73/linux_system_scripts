#!/bin/bash

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

declare -A CHECK_RESULTS
declare -A CHECK_VALUES
declare -A CHECK_DETAILS
declare -A CHECK_THRESHOLDS
declare -A CHECK_WEIGHTS
declare -a CHECK_ORDER

SCRIPT_START_TIME=$(date +%s)
OS_DISTRO=""
OS_VERSION=""
PACKAGE_MANAGER=""
SERVICE_MANAGER=""
TOTAL_CHECKS=0
COMPLETED_CHECKS=0
OVERALL_SCORE=0
PROGRESS_WIDTH=40
VERBOSE_MODE=true
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

load_telegram_config() {
    local config_file="/etc/system_scripts/auth.conf"
    if [ -f "$config_file" ]; then
        source "$config_file"
        if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ] && [ "$TELEGRAM_BOT_TOKEN" != "your_bot_token" ] && [ "$TELEGRAM_CHAT_ID" != "your_chat_id" ]; then
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

init_thresholds() {
    CHECK_THRESHOLDS[cpu_warning]=70
    CHECK_THRESHOLDS[cpu_critical]=90
    CHECK_THRESHOLDS[memory_warning]=80
    CHECK_THRESHOLDS[memory_critical]=95
    CHECK_THRESHOLDS[disk_warning]=80
    CHECK_THRESHOLDS[disk_critical]=95
    CHECK_THRESHOLDS[load_warning]=20
    CHECK_THRESHOLDS[load_critical]=50
    CHECK_THRESHOLDS[swap_warning]=50
    CHECK_THRESHOLDS[swap_critical]=80
    CHECK_THRESHOLDS[zombie_warning]=5
    CHECK_THRESHOLDS[zombie_critical]=20
    CHECK_WEIGHTS[system_core]=15
    CHECK_WEIGHTS[compute]=15
    CHECK_WEIGHTS[memory]=15
    CHECK_WEIGHTS[storage]=15
    CHECK_WEIGHTS[network]=10
    CHECK_WEIGHTS[services]=15
    CHECK_WEIGHTS[security]=10
    CHECK_WEIGHTS[updates]=5
}

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║              SYSTEM HEALTH DIAGNOSTIC                            ║'
    echo '║              Infrastructure Monitor                              ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${RESET}"
    echo -e "${DIM}Started: $(date '+%Y-%m-%d %H:%M:%S') | Host: $(hostname) | User: $(whoami)${RESET}"
    echo
}

print_section() {
    local title=$1
    echo -e "\n${BLUE}${BOLD}▶ ${title}${RESET}"
    echo -e "${BLUE}$(printf '─%.0s' $(seq 1 50))${RESET}"
}

print_subsection() {
    local title=$1
    echo -e "\n${MAGENTA}${BOLD}  ⧉ ${title}${RESET}"
}

status_icon() {
    local status=$1
    case $status in
        PASS) echo -e "${GREEN}✓${RESET}" ;;
        WARN) echo -e "${YELLOW}⚠${RESET}" ;;
        FAIL) echo -e "${RED}✗${RESET}" ;;
        INFO) echo -e "${BLUE}ℹ${RESET}" ;;
    esac
}

severity_badge() {
    local level=$1
    case $level in
        CRITICAL) echo -e "${BG_RED}${WHITE}${BOLD} CRITICAL ${RESET}" ;;
        WARNING)  echo -e "${BG_YELLOW}${BLACK}${BOLD} WARNING  ${RESET}" ;;
        HEALTHY)  echo -e "${BG_GREEN}${WHITE}${BOLD} HEALTHY  ${RESET}" ;;
        INFO)     echo -e "${BG_BLUE}${WHITE}${BOLD}  INFO    ${RESET}" ;;
    esac
}

print_detail_box() {
    local title=$1
    local content=$2
    echo -e "\n${BLUE}${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${BLUE}${BOLD}  ▸ $title${RESET}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "$content"
}

print_metric() {
    local label=$1
    local value=$2
    local status=$3
    
    if [ -z "$status" ]; then
        printf "    ${DIM}%-35s${RESET} %s\n" "$label:" "$value"
    else
        local color=$GREEN
        case "$status" in
            WARN) color=$YELLOW ;;
            FAIL) color=$RED ;;
            INFO) color=$BLUE ;;
        esac
        printf "    ${DIM}%-35s${RESET} ${color}%s${RESET}\n" "$label:" "$value"
    fi
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_DISTRO=$ID
        OS_VERSION=$VERSION_ID
        case $ID in
            ubuntu|debian|linuxmint|pop)
                PACKAGE_MANAGER="apt"
                SERVICE_MANAGER="systemd"
                ;;
            rhel|centos|fedora|rocky|almalinux|amzn)
                if [ -f /usr/bin/dnf ]; then
                    PACKAGE_MANAGER="dnf"
                else
                    PACKAGE_MANAGER="yum"
                fi
                SERVICE_MANAGER="systemd"
                ;;
            arch|manjaro)
                PACKAGE_MANAGER="pacman"
                SERVICE_MANAGER="systemd"
                ;;
            alpine)
                PACKAGE_MANAGER="apk"
                SERVICE_MANAGER="openrc"
                ;;
            opensuse*|suse*)
                PACKAGE_MANAGER="zypper"
                SERVICE_MANAGER="systemd"
                ;;
            *)
                PACKAGE_MANAGER="unknown"
                SERVICE_MANAGER="unknown"
                ;;
        esac
    elif [ -f /etc/redhat-release ]; then
        OS_DISTRO="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)
        PACKAGE_MANAGER="yum"
        SERVICE_MANAGER="systemd"
    elif [ -f /etc/debian_version ]; then
        OS_DISTRO="debian"
        OS_VERSION=$(cat /etc/debian_version)
        PACKAGE_MANAGER="apt"
        SERVICE_MANAGER="systemd"
    else
        OS_DISTRO="unknown"
        OS_VERSION="unknown"
        PACKAGE_MANAGER="unknown"
        SERVICE_MANAGER="unknown"
    fi
}

check_system_core() {
    local category="system_core"
    print_subsection "System Core Information"
    
    local kernel=$(uname -r)
    local arch=$(uname -m)
    local uptime_raw=$(cat /proc/uptime | awk '{print $1}')
    local uptime_days=$(echo "$uptime_raw / 86400" | bc)
    local uptime_hours=$(echo "($uptime_raw % 86400) / 3600" | bc)
    local uptime_mins=$(echo "($uptime_raw % 3600) / 60" | bc)
    local hostname=$(hostname)
    local timezone=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || date +%Z)
    local boot_time=$(who -b 2>/dev/null | awk '{print $3, $4}' || echo "N/A")
    local system_load=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    
    print_metric "Hostname" "$hostname"
    print_metric "Operating System" "${OS_DISTRO^} $OS_VERSION"
    print_metric "Kernel Version" "$kernel"
    print_metric "Architecture" "$arch"
    print_metric "System Uptime" "${uptime_days}d ${uptime_hours}h ${uptime_mins}m"
    print_metric "Last Boot Time" "$boot_time"
    print_metric "Timezone" "$timezone"
    print_metric "System Load (1m, 5m, 15m)" "$system_load"
    print_metric "Package Manager" "$PACKAGE_MANAGER"
    print_metric "Service Manager" "$SERVICE_MANAGER"
    
    CHECK_VALUES[$category]="kernel:$kernel|uptime:${uptime_days}d|boot:$boot_time|load:$system_load"
    CHECK_DETAILS[$category]="Hostname: $hostname | OS: ${OS_DISTRO^} $OS_VERSION | Kernel: $kernel"
    CHECK_RESULTS[$category]=PASS
    
    local score=100
    if [ $(echo "$uptime_days < 1" | bc) -eq 1 ]; then
        score=90
    fi
    
    echo $score
}

check_compute() {
    local category="compute"
    print_subsection "Compute Resources"
    
    local cpu_info=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
    local cpu_cores=$(nproc)
    local cpu_threads=$(grep -c ^processor /proc/cpuinfo)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local cpu_usage=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | sed 's/[^0-9.]//g')
    if [ -z "$cpu_usage" ]; then cpu_usage=0; fi
    local cpu_usage_int=$(echo "$cpu_usage" | cut -d'.' -f1)
    
    local zombie_count=$(ps aux | awk '{if ($8=="Z") print}' | wc -l)
    local process_count=$(ps aux | wc -l)
    local running_procs=$(ps aux | grep -v Z | wc -l)
    local cpu_temp="N/A"
    if command -v sensors &> /dev/null; then
        cpu_temp=$(sensors 2>/dev/null | grep 'Core' | head -1 | awk '{print $3}' | tr -d '+')
    fi
    
    print_metric "CPU Model" "$cpu_info"
    print_metric "Physical Cores" "$cpu_cores"
    print_metric "Logical Threads" "$cpu_threads"
    print_metric "Load Average (1m/5m/15m)" "$load_avg"
    print_metric "CPU Usage" "${cpu_usage_int}%"
    print_metric "CPU Temperature" "$cpu_temp"
    print_metric "Total Processes" "$process_count"
    print_metric "Running Processes" "$running_procs"
    print_metric "Zombie Processes" "$zombie_count"
    
    local status=PASS
    local issues=""
    
    if [ "$cpu_usage_int" -ge "${CHECK_THRESHOLDS[cpu_critical]}" ]; then
        status=FAIL
        issues="High CPU usage ($cpu_usage_int%)"
    elif [ "$cpu_usage_int" -ge "${CHECK_THRESHOLDS[cpu_warning]}" ]; then
        status=WARN
        issues="Elevated CPU usage ($cpu_usage_int%)"
    fi
    
    if [ "$zombie_count" -ge "${CHECK_THRESHOLDS[zombie_critical]}" ]; then
        status=FAIL
        issues="${issues}; Critical zombie processes ($zombie_count)"
    elif [ "$zombie_count" -ge "${CHECK_THRESHOLDS[zombie_warning]}" ] && [ "$status" = "PASS" ]; then
        status=WARN
        issues="${issues}; Zombie processes detected ($zombie_count)"
    fi
    
    local max_load=$(echo "$cpu_cores * ${CHECK_THRESHOLDS[load_critical]} / 10" | bc)
    if [ $(echo "$load_avg > $max_load" | bc) -eq 1 ]; then
        status=FAIL
        issues="${issues}, Critical load average"
    elif [ $(echo "$load_avg > $cpu_cores * ${CHECK_THRESHOLDS[load_warning]} / 10" | bc) -eq 1 ] && [ "$status" = "PASS" ]; then
        status=WARN
        issues="${issues}, High load average"
    fi
    
    CHECK_VALUES[$category]="usage:${cpu_usage_int}%|load:$load_avg|zombies:$zombie_count"
    CHECK_RESULTS[$category]=$status
    
    local score=100
    if [ "$status" = "FAIL" ]; then
        score=40
    elif [ "$status" = "WARN" ]; then
        score=75
    fi
    
    echo $score
}

check_memory() {
    local category="memory"
    print_subsection "Memory Analysis"
    
    local mem_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' | sed 's/[^0-9]//g')
    mem_total=$(echo "$mem_total" | sed 's/^0*//' | sed 's/^$/1/')
    local mem_used=$(free -m 2>/dev/null | awk '/^Mem:/{print $3}' | sed 's/[^0-9]//g')
    mem_used=$(echo "$mem_used" | sed 's/^0*//' | sed 's/^$/0/')
    local mem_available=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' | sed 's/[^0-9]//g')
    mem_available=$(echo "$mem_available" | sed 's/^0*//' | sed 's/^$/0/')
    local mem_buffers=$(free -m 2>/dev/null | awk '/^Mem:/{print $5}' | sed 's/[^0-9]//g')
    mem_buffers=$(echo "$mem_buffers" | sed 's/^0*//' | sed 's/^$/0/')
    local mem_cached=$(free -m 2>/dev/null | awk '/^Mem:/{print $6}' | sed 's/[^0-9]//g')
    mem_cached=$(echo "$mem_cached" | sed 's/^0*//' | sed 's/^$/0/')
    local mem_usage=$((mem_used * 100 / mem_total))
    local mem_usage_clean=$(echo "$mem_usage" | sed 's/[^0-9]//g' | tr -d '\n')
    
    local swap_total=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}' | sed 's/[^0-9]//g')
    swap_total=$(echo "$swap_total" | sed 's/^0*//' | sed 's/^$/0/')
    local swap_used=$(free -m 2>/dev/null | awk '/^Swap:/{print $3}' | sed 's/[^0-9]//g')
    swap_used=$(echo "$swap_used" | sed 's/^0*//' | sed 's/^$/0/')
    local swap_free=$(free -m 2>/dev/null | awk '/^Swap:/{print $4}' | sed 's/[^0-9]//g')
    swap_free=$(echo "$swap_free" | sed 's/^0*//' | sed 's/^$/0/')
    local swap_usage=0
    if [ "$swap_total" -gt 0 ]; then
        swap_usage=$((swap_used * 100 / swap_total))
    fi
    local swap_usage_clean=$(echo "$swap_usage" | sed 's/[^0-9]//g' | tr -d '\n')
    
    local oom_kills=$(dmesg 2>/dev/null | grep -c "Out of memory" | tr -d '\n')
    local page_faults=$(grep "pgfault" /proc/vmstat 2>/dev/null | awk '{print $2}' || echo "0")
    
    print_metric "Total Memory (RAM)" "${mem_total} MB"
    print_metric "Used Memory" "${mem_used} MB ($(( mem_used * 100 / mem_total ))%)"
    print_metric "Available Memory" "${mem_available} MB"
    print_metric "Buffers" "${mem_buffers} MB"
    print_metric "Cached" "${mem_cached} MB"
    print_metric "Memory Usage Percentage" "${mem_usage_clean}%"
    
    if [ "$swap_total" -gt 0 ]; then
        print_metric "Swap Total" "${swap_total} MB"
        print_metric "Swap Used" "${swap_used} MB (${swap_usage_clean}%)"
        print_metric "Swap Free" "${swap_free} MB"
    else
        print_metric "Swap" "Disabled"
    fi
    
    print_metric "OOM Kills" "$oom_kills"
    print_metric "Page Faults" "$page_faults"
    
    local status=PASS
    
    if [[ "$mem_usage_clean" -ge "${CHECK_THRESHOLDS[memory_critical]}" ]]; then
        status=FAIL
    elif [[ "$mem_usage_clean" -ge "${CHECK_THRESHOLDS[memory_warning]}" ]]; then
        status=WARN
    fi
    
    if [[ "$swap_usage_clean" -ge "${CHECK_THRESHOLDS[swap_critical]}" ]]; then
        status=FAIL
    elif [[ "$swap_usage_clean" -ge "${CHECK_THRESHOLDS[swap_warning]}" ]] && [ "$status" = "PASS" ]; then
        status=WARN
    fi
    
    if [ "$oom_kills" -gt 0 ]; then
        status=FAIL
    fi
    
    CHECK_VALUES[$category]="usage:${mem_usage_clean}%|swap:${swap_usage_clean}%|oom:$oom_kills"
    CHECK_RESULTS[$category]=$status
    
    local score=100
    if [ "$status" = "FAIL" ]; then
        score=30
    elif [ "$status" = "WARN" ]; then
        score=70
    fi
    
    echo $score
}

check_storage() {
    local category="storage"
    print_subsection "Storage Health"
    
    local max_usage=0
    local max_fs=""
    local fail_count=0
    local warn_count=0
    
    echo -e "    ${DIM}Filesystem          Size    Used    Avail   Use%    Mounted on${RESET}"
    
    while read -r filesystem size used avail usage mount; do
        [ "$filesystem" = "Filesystem" ] && continue
        [ -z "$filesystem" ] && continue
        
        local usage_num=${usage%\%}
        
        local color=$GREEN
        local status_icon="✓"
        if [ $usage_num -ge ${CHECK_THRESHOLDS[disk_critical]} ]; then
            color=$RED
            status_icon="✗"
            ((fail_count++))
        elif [ $usage_num -ge ${CHECK_THRESHOLDS[disk_warning]} ]; then
            color=$YELLOW
            status_icon="⚠"
            ((warn_count++))
        fi
        
        printf "    ${color}%-20s %-7s %-7s %-7s %-6s${RESET} %s\n" \
            "$filesystem" "$size" "$used" "$avail" "$usage" "$mount"
        
        if [ $usage_num -gt $max_usage ]; then
            max_usage=$usage_num
            max_fs="$mount"
        fi
    done < <(df -h | grep -E '^/dev/')
    
    local inode_check=$(df -i 2>/dev/null | awk 'NR>1 && $5+0 > 90 {print}' | wc -l)
    if [ $inode_check -gt 0 ]; then
        echo -e "    ${YELLOW}⚠ Warning: $inode_check filesystem(s) with >90% inode usage${RESET}"
    fi
    
    local status=PASS
    if [ $fail_count -gt 0 ]; then
        status=FAIL
    elif [ $warn_count -gt 0 ]; then
        status=WARN
    fi
    
    CHECK_VALUES[$category]="max_usage:${max_usage}%|filesystem:$max_fs|failures:$fail_count"
    CHECK_RESULTS[$category]=$status
    
    local score=100
    if [ "$status" = "FAIL" ]; then
        score=25
    elif [ "$status" = "WARN" ]; then
        score=65
    fi
    
    echo $score
}

check_network() {
    local category="network"
    print_subsection "Network Status"
    
    local default_iface=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
    local default_gateway=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
    local public_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "N/A")
    local dns_servers=$(grep -E "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -3 | tr '\n' ' ')
    
    printf "    ${DIM}%-20s${RESET} %s\n" "Default Interface:" "$default_iface"
    printf "    ${DIM}%-20s${RESET} %s\n" "Default Gateway:" "$default_gateway"
    printf "    ${DIM}%-20s${RESET} %s\n" "Public IP:" "$public_ip"
    printf "    ${DIM}%-20s${RESET} %s\n" "DNS Servers:" "$dns_servers"
    
    local listening_ports=$(ss -tuln 2>/dev/null | wc -l)
    local established_conn=$(ss -t state established 2>/dev/null | wc -l)
    
    printf "    ${DIM}%-20s${RESET} %s\n" "Listening Ports:" "$listening_ports"
    printf "    ${DIM}%-20s${RESET} %s\n" "Established Conn:" "$established_conn"
    
    local status=PASS
    
    if [ -z "$default_iface" ] || [ -z "$default_gateway" ]; then
        status=WARN
    fi
    
    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        status=WARN
    fi
    
    CHECK_VALUES[$category]="iface:$default_iface|gateway:$default_gateway|public_ip:$public_ip"
    CHECK_RESULTS[$category]=$status
    
    local score=100
    if [ "$status" = "WARN" ]; then
        score=80
    fi
    
    echo $score
}

check_services() {
    local category="services"
    print_subsection "Critical Services"
    
    local services=("sshd" "cron" "systemd-journald" "networking" "rsyslog")
    local failed_services=()
    local running_count=0
    
    for service in "${services[@]}"; do
        local status_text
        local color
        
        if systemctl is-active --quiet $service 2>/dev/null; then
            status_text="RUNNING"
            color=$GREEN
            ((running_count++))
        else
            status_text="STOPPED"
            color=$RED
            failed_services+=("$service")
        fi
        
        printf "    ${DIM}%-20s${RESET} ${color}%-10s${RESET}\n" "$service:" "$status_text"
    done
    
    local failed_count=${#failed_services[@]}
    local status=PASS
    
    if [ $failed_count -gt 2 ]; then
        status=FAIL
    elif [ $failed_count -gt 0 ]; then
        status=WARN
    fi
    
    # Convert failed services array to string
    local failed_list="none"
    if [ $failed_count -gt 0 ]; then
        failed_list=$(IFS=, ; echo "${failed_services[*]}")
    fi
    
    CHECK_VALUES[$category]="running:$running_count|failed:$failed_count"
    CHECK_DETAILS[$category]="failed_services:$failed_list"
    CHECK_RESULTS[$category]=$status
    
    local score=100
    if [ "$status" = "FAIL" ]; then
        score=50
    elif [ "$status" = "WARN" ]; then
        score=85
    fi
    
    echo $score
}

check_security() {
    local category="security"
    print_subsection "Security Audit"
    
    local failed_logins=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null | tr -d '\n')
    local selinux_status=$(getenforce 2>/dev/null || echo "N/A")
    local apparmor_status=$(aa-status --enabled 2>/dev/null && echo "ENABLED" || echo "DISABLED")
    local firewall_status=$(iptables -L 2>/dev/null | head -1 | grep -q "Chain INPUT" && echo "ACTIVE" || echo "INACTIVE")
    local open_ports=$(ss -tuln 2>/dev/null | grep LISTEN | wc -l)
    
    printf "    ${DIM}%-20s${RESET} %s\n" "Failed Logins:" "$failed_logins"
    printf "    ${DIM}%-20s${RESET} %s\n" "SELinux Status:" "$selinux_status"
    printf "    ${DIM}%-20s${RESET} %s\n" "AppArmor Status:" "$apparmor_status"
    printf "    ${DIM}%-20s${RESET} %s\n" "Firewall Status:" "$firewall_status"
    printf "    ${DIM}%-20s${RESET} %s\n" "Open Ports:" "$open_ports"
    
    local status=PASS
    
    if [[ "$failed_logins" -gt 10 ]]; then
        status=WARN
    fi
    
    if [ "$firewall_status" = "INACTIVE" ]; then
        status=WARN
    fi
    
    CHECK_VALUES[$category]="failed_logins:$failed_logins|firewall:$firewall_status|ports:$open_ports"
    CHECK_RESULTS[$category]=$status
    
    local score=100
    if [ "$status" = "WARN" ]; then
        score=85
    fi
    
    echo $score
}

check_updates() {
    local category="updates"
    print_subsection "System Updates"
    
    local pending_updates=0
    local security_updates=0
    local reboot_required="NO"
    
    case $PACKAGE_MANAGER in
        apt)
            pending_updates=$(apt list --upgradable 2>/dev/null | wc -l)
            if [ -f /var/run/reboot-required ]; then
                reboot_required="YES"
            fi
            ;;
        dnf|yum)
            pending_updates=$(dnf check-update --refresh 2>/dev/null | grep -v "^$" | wc -l)
            if [ -f /var/run/reboot-required ]; then
                reboot_required="YES"
            fi
            ;;
        pacman)
            pending_updates=$(pacman -Qu 2>/dev/null | wc -l)
            ;;
        *)
            pending_updates="N/A"
            ;;
    esac
    
    [ -f /var/run/reboot-required ] && reboot_required="YES"
    
    printf "    ${DIM}%-20s${RESET} %s\n" "Package Manager:" "$PACKAGE_MANAGER"
    printf "    ${DIM}%-20s${RESET} %s\n" "Pending Updates:" "$pending_updates"
    printf "    ${DIM}%-20s${RESET} %s\n" "Reboot Required:" "$reboot_required"
    
    local status=PASS
    
    if [ "$reboot_required" = "YES" ]; then
        status=WARN
    fi
    
    if [ "$pending_updates" != "N/A" ] && [ $pending_updates -gt 50 ]; then
        status=WARN
    fi
    
    CHECK_VALUES[$category]="pending:$pending_updates|reboot:$reboot_required"
    CHECK_RESULTS[$category]=$status
    
    local score=100
    if [ "$status" = "WARN" ]; then
        score=90
    fi
    
    echo $score
}

execute_check() {
    local check_name=$1
    local check_func=$2
    local weight=$3
    
    ((COMPLETED_CHECKS++))
    
    local score
    $check_func > /tmp/check_output.txt 2>&1
    score=$(tail -1 /tmp/check_output.txt)
    
    OVERALL_SCORE=$((OVERALL_SCORE + score * weight / 100))
    
    local filled=$((COMPLETED_CHECKS * PROGRESS_WIDTH / TOTAL_CHECKS))
    local empty=$((PROGRESS_WIDTH - filled))
    
    printf "\r${DIM}[${RESET}"
    printf "${GREEN}%0.s█" $(seq 1 $filled)
    printf "${DIM}%0.s░" $(seq 1 $empty)
    printf "${DIM}]${RESET} ${CYAN}%d/%d${RESET}" "$COMPLETED_CHECKS" "$TOTAL_CHECKS"
    
    printf ""
}

print_summary() {
    echo -e "\n${CYAN}${BOLD}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║                   HEALTH REPORT                                  ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${RESET}"
    
    local end_time=$(date +%s)
    local duration=$((end_time - SCRIPT_START_TIME))
    
    print_metric "Scan Duration" "${duration}s"
    print_metric "Total Checks Performed" "$TOTAL_CHECKS"
    print_metric "OS Distribution" "${OS_DISTRO^} $OS_VERSION"
    print_metric "Package Manager" "$PACKAGE_MANAGER"
    print_metric "Scan Timestamp" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    
    echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}DETAILED CATEGORY RESULTS:${RESET}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    
    local pass_count=0
    local warn_count=0
    local fail_count=0
    
    for category in "${CHECK_ORDER[@]}"; do
        local result=${CHECK_RESULTS[$category]}
        local values=${CHECK_VALUES[$category]}
        local icon=$(status_icon $result)
        local display_name="${category//_/ }"
        display_name=$(echo "$display_name" | sed 's/\b\w/\u&/g')
        
        local color=$GREEN
        case "$result" in
            WARN) color=$YELLOW ;;
            FAIL) color=$RED ;;
        esac
        
        echo -e "\n  ${color}${BOLD}${icon}${RESET} ${BOLD}${display_name}${RESET}"
        echo -e "    Status: ${color}${result}${RESET}"
        if [ ! -z "$values" ]; then
            echo -e "    Details: ${DIM}${values}${RESET}"
            if [ ! -z "${CHECK_DETAILS[$category]}" ]; then
               echo -e "    ${YELLOW}Affected:${RESET} ${CHECK_DETAILS[$category]}"
            fi
        fi
        
        case $result in
            PASS) ((pass_count++)) ;;
            WARN) ((warn_count++)) ;;
            FAIL) ((fail_count++)) ;;
        esac
    done
    
    echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    
    local final_status="HEALTHY"
    local status_color=$GREEN
    
    if [ $fail_count -gt 0 ]; then
        final_status="CRITICAL"
        status_color=$RED
    elif [ $warn_count -gt 0 ]; then
        final_status="WARNING"
        status_color=$YELLOW
    fi
    
    echo -e "\n${BOLD}HEALTH METRICS:${RESET}"
    echo -e "  ${BOLD}Overall Score:${RESET} ${status_color}${OVERALL_SCORE}/100${RESET}"
    echo -e "  ${BOLD}System Status:${RESET} $(severity_badge $final_status)"
    
    echo -e "\n${BOLD}CHECK SUMMARY:${RESET}"
    echo -e "  ${GREEN}✓ Passed Checks:${RESET}   $pass_count"
    echo -e "  ${YELLOW}⚠ Warning Checks:${RESET}  $warn_count"
    echo -e "  ${RED}✗ Failed Checks:${RESET}   $fail_count"
    echo -e "  ${BLUE}ℹ Total Checks:${RESET}    $TOTAL_CHECKS"
    
    local pass_percentage=$((pass_count * 100 / TOTAL_CHECKS))
    echo -e "\n${BOLD}Success Rate:${RESET} ${GREEN}${pass_percentage}%${RESET}"
    
    echo -e "\n${CYAN}${BOLD}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║                  RECOMMENDATIONS & ACTIONS                       ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${RESET}"
    
    if [ $fail_count -gt 0 ]; then
        echo -e "\n${RED}${BOLD}⚡ CRITICAL ISSUES DETECTED${RESET}"
        echo -e "    ${RED}• Immediate action required for ${fail_count} failed check(s)${RESET}"
        echo -e "    ${RED}• System stability may be compromised${RESET}"
        echo -e "    ${RED}• Investigate and resolve immediately${RESET}"
    fi
    
    if [ $warn_count -gt 0 ]; then
        echo -e "\n${YELLOW}${BOLD}⚠️  WARNING CONDITIONS DETECTED${RESET}"
        echo -e "    ${YELLOW}• ${warn_count} warning(s) require attention${RESET}"
        echo -e "    ${YELLOW}• Review and monitor within 24 hours${RESET}"
        echo -e "    ${YELLOW}• Consider preventive maintenance${RESET}"
    fi
    
    if [ $fail_count -eq 0 ] && [ $warn_count -eq 0 ]; then
        echo -e "\n${GREEN}${BOLD}✓ ALL SYSTEMS OPERATIONAL${RESET}"
        echo -e "    ${GREEN}• System is running optimally${RESET}"
        echo -e "    ${GREEN}• No immediate action required${RESET}"
        echo -e "    ${GREEN}• Continue routine monitoring${RESET}"
    fi
    
    if [ "${CHECK_RESULTS[storage]}" = "WARN" ] || [ "${CHECK_RESULTS[storage]}" = "FAIL" ]; then
        echo -e "\n    ${YELLOW}→ Check storage space and cleanup old files${RESET}"
    fi
    
    if [ "${CHECK_RESULTS[compute]}" = "WARN" ] || [ "${CHECK_RESULTS[compute]}" = "FAIL" ]; then
        echo -e "    ${YELLOW}→ Monitor CPU usage and terminate resource-heavy processes${RESET}"
    fi
    
    if [ "${CHECK_RESULTS[memory]}" = "WARN" ] || [ "${CHECK_RESULTS[memory]}" = "FAIL" ]; then
        echo -e "    ${YELLOW}→ Review memory usage and consider system upgrade${RESET}"
    fi
    
    if [ "${CHECK_RESULTS[security]}" = "WARN" ]; then
        echo -e "    ${YELLOW}→ Review security audit logs and firewall rules${RESET}"
    fi
    
    if [ "${CHECK_RESULTS[updates]}" = "WARN" ]; then
        echo -e "    ${YELLOW}→ Apply pending system and security updates${RESET}"
    fi
    
    echo -e "\n${DIM}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${DIM}Report Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
    echo -e "${DIM}Hostname: $(hostname) | System Uptime: $(uptime -p 2>/dev/null || echo 'N/A')${RESET}"
    echo -e "${DIM}═══════════════════════════════════════════════════════════════${RESET}\n"
}

main() {
    init_thresholds
    detect_distro
    
    CHECK_ORDER=("system_core" "compute" "memory" "storage" "network" "services" "security" "updates")
    TOTAL_CHECKS=${#CHECK_ORDER[@]}
    
    print_header
    
    print_section "SYSTEM HEALTH DIAGNOSTICS"
    
    execute_check "System Core" check_system_core ${CHECK_WEIGHTS[system_core]}
    execute_check "Compute" check_compute ${CHECK_WEIGHTS[compute]}
    execute_check "Memory" check_memory ${CHECK_WEIGHTS[memory]}
    execute_check "Storage" check_storage ${CHECK_WEIGHTS[storage]}
    execute_check "Network" check_network ${CHECK_WEIGHTS[network]}
    execute_check "Services" check_services ${CHECK_WEIGHTS[services]}
    execute_check "Security" check_security ${CHECK_WEIGHTS[security]}
    execute_check "Updates" check_updates ${CHECK_WEIGHTS[updates]}
    
    print_summary
    
    if load_telegram_config; then
        echo -e "\n${CYAN}Sending report to Telegram...${RESET}"
        local telegram_message="<b>System Health Report</b>%0A"
        telegram_message+="<b>Status:</b> $([ "${fail_count:-0}" -gt 0 ] && echo "CRITICAL" || ([ "${warn_count:-0}" -gt 0 ] && echo "WARNING" || echo "HEALTHY"))%0A"
        telegram_message+="<b>Score:</b> ${OVERALL_SCORE}/100%0A"
        telegram_message+="<b>Passed:</b> ${pass_count:-0} | <b>Warnings:</b> ${warn_count:-0} | <b>Failed:</b> ${fail_count:-0}%0A"
        telegram_message+="<b>Host:</b> $(hostname)%0A"
        telegram_message+="<b>Time:</b> $(date '+%Y-%m-%d %H:%M:%S %Z')"
        
        if send_telegram_message "$telegram_message"; then
            echo -e "${GREEN}Report sent to Telegram successfully!${RESET}"
        else
            echo -e "${RED}Failed to send report to Telegram. Check bot token and chat ID.${RESET}"
        fi
    else
        echo -e "\n${YELLOW}⚠ Telegram configuration not found. Skipping Telegram notification.${RESET}"
        echo -e "${DIM}To enable Telegram notifications, create /etc/system_scripts/auth.conf with:${RESET}"
        echo -e "${DIM}  TELEGRAM_BOT_TOKEN=\"your_bot_token\"${RESET}"
        echo -e "${DIM}  TELEGRAM_CHAT_ID=\"your_chat_id\"${RESET}"
    fi
}

main "$@"
