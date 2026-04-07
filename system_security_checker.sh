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
    # Security thresholds - higher standards
    CHECK_WEIGHTS[ssh_hardening]=15
    CHECK_WEIGHTS[privilege_escalation]=15
    CHECK_WEIGHTS[brute_force_protection]=15
    CHECK_WEIGHTS[mandatory_access_control]=10
    CHECK_WEIGHTS[audit_coverage]=10
    CHECK_WEIGHTS[file_integrity]=10
    CHECK_WEIGHTS[firewall_policy]=10
    CHECK_WEIGHTS[kernel_hardening]=5
    CHECK_WEIGHTS[service_sandboxing]=5
    CHECK_WEIGHTS[temp_directories]=5
}

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║              SYSTEM SECURITY AUDIT                              ║'
    echo '║              Infrastructure Security Checker                    ║'
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
        SECURE)   echo -e "${BG_GREEN}${WHITE}${BOLD} SECURE   ${RESET}" ;;
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

# Security Check Functions

check_ssh_hardening() {
    print_subsection "SSH Hardening Check"

    local score=100
    local issues=""
    local details=""

    # Check if SSH is running
    if ! systemctl is-active --quiet sshd 2>/dev/null && ! systemctl is-active --quiet ssh 2>/dev/null; then
        echo -e "    ${YELLOW}SSH service not running - skipping SSH checks${RESET}"
        CHECK_RESULTS[ssh_hardening]="INFO"
        CHECK_VALUES[ssh_hardening]="SSH not running"
        echo 75  # Partial score for not running SSH
        return
    fi

    # Read effective SSH config
    local ssh_config=""
    if command -v sshd >/dev/null 2>&1; then
        ssh_config=$(sshd -T 2>/dev/null)
    else
        ssh_config=$(cat /etc/ssh/sshd_config 2>/dev/null)
    fi

    # Check root login
    if echo "$ssh_config" | grep -q "permitrootlogin.*yes\|permitrootlogin.*without-password" || ! echo "$ssh_config" | grep -q "permitrootlogin"; then
        issues="${issues}Root login allowed; "
        score=$((score - 20))
    fi

    # Check password authentication
    if echo "$ssh_config" | grep -q "passwordauthentication.*yes" || ! echo "$ssh_config" | grep -q "passwordauthentication"; then
        issues="${issues}Password auth enabled; "
        score=$((score - 15))
    fi

    # Check for weak ciphers
    if echo "$ssh_config" | grep -q "ciphers.*\(3des\|blowfish\|arcfour\|cast128\)" || ! echo "$ssh_config" | grep -q "ciphers"; then
        issues="${issues}Weak ciphers allowed; "
        score=$((score - 10))
    fi

    # Check idle timeout
    if ! echo "$ssh_config" | grep -q "clientaliveinterval\|clientalivecountmax"; then
        issues="${issues}No idle timeout configured; "
        score=$((score - 10))
    fi

    # Check for key-based auth requirement
    if ! echo "$ssh_config" | grep -q "authenticationmethods.*publickey"; then
        issues="${issues}Key-based auth not enforced; "
        score=$((score - 10))
    fi

    if [ $score -ge 90 ]; then
        CHECK_RESULTS[ssh_hardening]="PASS"
        CHECK_VALUES[ssh_hardening]="SSH properly hardened"
    elif [ $score -ge 70 ]; then
        CHECK_RESULTS[ssh_hardening]="WARN"
        CHECK_VALUES[ssh_hardening]="SSH partially hardened"
        CHECK_DETAILS[ssh_hardening]="${issues% }"
    else
        CHECK_RESULTS[ssh_hardening]="FAIL"
        CHECK_VALUES[ssh_hardening]="SSH hardening required"
        CHECK_DETAILS[ssh_hardening]="${issues% }"
    fi

    echo $score
}

check_privilege_escalation() {
    print_subsection "Privilege Escalation Check"

    local score=100
    local issues=""
    local details=""

    # Check sudoers
    if [ -f /etc/sudoers ]; then
        # Check for NOPASSWD
        if grep -q "NOPASSWD" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
            issues="${issues}NOPASSWD entries found; "
            score=$((score - 25))
        fi

        # Check for ALL=(ALL) grants
        if grep -q "ALL=(ALL).*ALL" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
            issues="${issues}Broad ALL permissions found; "
            score=$((score - 20))
        fi

        # Check for command wildcards
        if grep -q "\*" /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -v "^#"; then
            issues="${issues}Command wildcards detected; "
            score=$((score - 15))
        fi

        # Check env_reset
        if ! grep -q "env_reset" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
            issues="${issues}env_reset not enabled; "
            score=$((score - 10))
        fi
    else
        issues="${issues}No sudoers file found; "
        score=$((score - 50))
    fi

    # Check for suid binaries
    local suid_count=$(find /usr/bin /bin /sbin /usr/sbin -perm /4000 2>/dev/null | wc -l)
    if [ $suid_count -gt 50 ]; then
        issues="${issues}High number of SUID binaries ($suid_count); "
        score=$((score - 10))
    fi

    if [ $score -ge 90 ]; then
        CHECK_RESULTS[privilege_escalation]="PASS"
        CHECK_VALUES[privilege_escalation]="Privilege escalation protected"
    elif [ $score -ge 70 ]; then
        CHECK_RESULTS[privilege_escalation]="WARN"
        CHECK_VALUES[privilege_escalation]="Some privilege risks detected"
        CHECK_DETAILS[privilege_escalation]="${issues% }"
    else
        CHECK_RESULTS[privilege_escalation]="FAIL"
        CHECK_VALUES[privilege_escalation]="Privilege escalation vulnerabilities"
        CHECK_DETAILS[privilege_escalation]="${issues% }"
    fi

    echo $score
}

check_brute_force_protection() {
    print_subsection "Brute Force Protection Check"

    local score=100
    local issues=""
    local details=""

    # Check PAM faillock
    if [ -f /etc/security/faillock.conf ]; then
        local deny_count=$(grep "^deny =" /etc/security/faillock.conf | awk '{print $3}')
        local fail_interval=$(grep "^fail_interval =" /etc/security/faillock.conf | awk '{print $3}')
        local unlock_time=$(grep "^unlock_time =" /etc/security/faillock.conf | awk '{print $3}')

        if [ -z "$deny_count" ] || [ "$deny_count" -gt 5 ]; then
            issues="${issues}Weak deny count ($deny_count); "
            score=$((score - 15))
        fi

        if [ -z "$fail_interval" ] || [ "$fail_interval" -gt 900 ]; then
            issues="${issues}Long fail interval ($fail_interval); "
            score=$((score - 10))
        fi

        if [ -z "$unlock_time" ] || [ "$unlock_time" -lt 600 ]; then
            issues="${issues}Short unlock time ($unlock_time); "
            score=$((score - 10))
        fi

        # Check if root is specially treated
        if grep -q "even_deny_root" /etc/security/faillock.conf; then
            score=$((score + 5))  # Bonus for treating root same
        fi
    else
        issues="${issues}faillock.conf not found; "
        score=$((score - 30))
    fi

    # Check if PAM modules are configured
    if ! grep -q "pam_faillock" /etc/pam.d/* 2>/dev/null; then
        issues="${issues}PAM faillock not configured; "
        score=$((score - 25))
    fi

    if [ $score -ge 90 ]; then
        CHECK_RESULTS[brute_force_protection]="PASS"
        CHECK_VALUES[brute_force_protection]="Brute force protection active"
    elif [ $score -ge 70 ]; then
        CHECK_RESULTS[brute_force_protection]="WARN"
        CHECK_VALUES[brute_force_protection]="Brute force protection weak"
        CHECK_DETAILS[brute_force_protection]="${issues% }"
    else
        CHECK_RESULTS[brute_force_protection]="FAIL"
        CHECK_VALUES[brute_force_protection]="No brute force protection"
        CHECK_DETAILS[brute_force_protection]="${issues% }"
    fi

    echo $score
}

check_mandatory_access_control() {
    print_subsection "Mandatory Access Control Check"

    local score=100
    local issues=""
    local details=""

    case $OS_DISTRO in
        rhel|centos|fedora|rocky|almalinux|amzn)
            # SELinux check
            if command -v getenforce >/dev/null 2>&1; then
                local selinux_status=$(getenforce)
                if [ "$selinux_status" = "Enforcing" ]; then
                    CHECK_RESULTS[mandatory_access_control]="PASS"
                    CHECK_VALUES[mandatory_access_control]="SELinux enforcing"
                    score=100
                elif [ "$selinux_status" = "Permissive" ]; then
                    CHECK_RESULTS[mandatory_access_control]="WARN"
                    CHECK_VALUES[mandatory_access_control]="SELinux in permissive mode"
                    CHECK_DETAILS[mandatory_access_control]="SELinux should be enforcing"
                    score=60
                else
                    CHECK_RESULTS[mandatory_access_control]="FAIL"
                    CHECK_VALUES[mandatory_access_control]="SELinux disabled"
                    CHECK_DETAILS[mandatory_access_control]="SELinux should be enabled and enforcing"
                    score=20
                fi
            else
                CHECK_RESULTS[mandatory_access_control]="FAIL"
                CHECK_VALUES[mandatory_access_control]="SELinux not installed"
                CHECK_DETAILS[mandatory_access_control]="Install and enable SELinux"
                score=10
            fi
            ;;
        ubuntu|debian|linuxmint|pop)
            # AppArmor check
            if command -v apparmor_status >/dev/null 2>&1; then
                local apparmor_output=$(apparmor_status 2>/dev/null)
                local enforcing_profiles=$(echo "$apparmor_output" | grep -c "enforce")
                local complain_profiles=$(echo "$apparmor_output" | grep -c "complain")

                if [ $enforcing_profiles -gt 0 ] && [ $complain_profiles -eq 0 ]; then
                    CHECK_RESULTS[mandatory_access_control]="PASS"
                    CHECK_VALUES[mandatory_access_control]="AppArmor enforcing ($enforcing_profiles profiles)"
                    score=100
                elif [ $enforcing_profiles -gt 0 ]; then
                    CHECK_RESULTS[mandatory_access_control]="WARN"
                    CHECK_VALUES[mandatory_access_control]="AppArmor mixed mode ($enforcing_profiles enforce, $complain_profiles complain)"
                    CHECK_DETAILS[mandatory_access_control]="Some profiles in complain mode"
                    score=70
                else
                    CHECK_RESULTS[mandatory_access_control]="FAIL"
                    CHECK_VALUES[mandatory_access_control]="AppArmor not enforcing"
                    CHECK_DETAILS[mandatory_access_control]="No enforcing AppArmor profiles"
                    score=30
                fi
            else
                CHECK_RESULTS[mandatory_access_control]="FAIL"
                CHECK_VALUES[mandatory_access_control]="AppArmor not available"
                CHECK_DETAILS[mandatory_access_control]="Install and enable AppArmor"
                score=10
            fi
            ;;
        *)
            CHECK_RESULTS[mandatory_access_control]="INFO"
            CHECK_VALUES[mandatory_access_control]="MAC not applicable for $OS_DISTRO"
            score=75
            ;;
    esac

    echo $score
}

check_audit_coverage() {
    print_subsection "Audit Coverage Check"

    local score=100
    local issues=""
    local details=""

    # Check if auditd is running
    if ! systemctl is-active --quiet auditd 2>/dev/null; then
        CHECK_RESULTS[audit_coverage]="FAIL"
        CHECK_VALUES[audit_coverage]="Audit daemon not running"
        CHECK_DETAILS[audit_coverage]="Start auditd service"
        echo 10
        return
    fi

    # Check audit rules
    local rules_file="/etc/audit/audit.rules"
    local rules_count=0

    if [ -f "$rules_file" ]; then
        rules_count=$(grep -v "^#" "$rules_file" | grep -v "^$" | wc -l)
    fi

    if [ $rules_count -lt 10 ]; then
        issues="${issues}Very few audit rules ($rules_count); "
        score=$((score - 40))
    elif [ $rules_count -lt 20 ]; then
        issues="${issues}Limited audit rules ($rules_count); "
        score=$((score - 20))
    fi

    # Check for key security events
    local key_rules=("identity" "account" "session" "privilege" "module" "syscall")
    for rule in "${key_rules[@]}"; do
        if ! grep -q "$rule" "$rules_file" 2>/dev/null; then
            issues="${issues}Missing $rule auditing; "
            score=$((score - 5))
        fi
    done

    # Check audit log size
    local max_log_size=$(grep "^max_log_file" /etc/audit/auditd.conf 2>/dev/null | awk '{print $3}')
    if [ -n "$max_log_size" ] && [ "$max_log_size" -lt 10 ]; then
        issues="${issues}Small audit log size (${max_log_size}MB); "
        score=$((score - 10))
    fi

    if [ $score -ge 90 ]; then
        CHECK_RESULTS[audit_coverage]="PASS"
        CHECK_VALUES[audit_coverage]="Comprehensive audit coverage ($rules_count rules)"
    elif [ $score -ge 70 ]; then
        CHECK_RESULTS[audit_coverage]="WARN"
        CHECK_VALUES[audit_coverage]="Partial audit coverage ($rules_count rules)"
        CHECK_DETAILS[audit_coverage]="${issues% }"
    else
        CHECK_RESULTS[audit_coverage]="FAIL"
        CHECK_VALUES[audit_coverage]="Insufficient audit coverage ($rules_count rules)"
        CHECK_DETAILS[audit_coverage]="${issues% }"
    fi

    echo $score
}

check_file_integrity() {
    print_subsection "File Integrity Monitoring Check"

    local score=100
    local issues=""
    local details=""

    # Check if AIDE is installed
    if ! command -v aide >/dev/null 2>&1; then
        CHECK_RESULTS[file_integrity]="FAIL"
        CHECK_VALUES[file_integrity]="AIDE not installed"
        CHECK_DETAILS[file_integrity]="Install AIDE for file integrity monitoring"
        echo 20
        return
    fi

    # Check if AIDE database exists
    local aide_db="/var/lib/aide/aide.db"
    if [ ! -f "$aide_db" ]; then
        issues="${issues}AIDE database not initialized; "
        score=$((score - 40))
    fi

    # Check when AIDE was last run
    local aide_log="/var/log/aide/aide.log"
    if [ -f "$aide_log" ]; then
        local last_run=$(stat -c %Y "$aide_log" 2>/dev/null)
        local now=$(date +%s)
        local days_since=$(( (now - last_run) / 86400 ))

        if [ $days_since -gt 7 ]; then
            issues="${issues}AIDE not run recently (${days_since} days ago); "
            score=$((score - 20))
        fi
    else
        issues="${issues}AIDE never run; "
        score=$((score - 30))
    fi

    # Check AIDE configuration
    local aide_conf="/etc/aide/aide.conf"
    if [ -f "$aide_conf" ]; then
        local monitored_paths=$(grep "^/" "$aide_conf" | grep -v "^#" | wc -l)
        if [ $monitored_paths -lt 5 ]; then
            issues="${issues}Few paths monitored ($monitored_paths); "
            score=$((score - 15))
        fi
    fi

    if [ $score -ge 90 ]; then
        CHECK_RESULTS[file_integrity]="PASS"
        CHECK_VALUES[file_integrity]="File integrity monitoring active"
    elif [ $score -ge 70 ]; then
        CHECK_RESULTS[file_integrity]="WARN"
        CHECK_VALUES[file_integrity]="File integrity monitoring partial"
        CHECK_DETAILS[file_integrity]="${issues% }"
    else
        CHECK_RESULTS[file_integrity]="FAIL"
        CHECK_VALUES[file_integrity]="File integrity monitoring inadequate"
        CHECK_DETAILS[file_integrity]="${issues% }"
    fi

    echo $score
}

check_firewall_policy() {
    print_subsection "Firewall Policy Check"

    local score=100
    local issues=""
    local details=""
    local firewall_type="none"

    # Detect firewall type
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        firewall_type="ufw"
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q "running"; then
        firewall_type="firewalld"
    elif command -v iptables >/dev/null 2>&1 && iptables -L 2>/dev/null | grep -q "Chain"; then
        firewall_type="iptables"
    elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -q "table"; then
        firewall_type="nftables"
    fi

    if [ "$firewall_type" = "none" ]; then
        CHECK_RESULTS[firewall_policy]="FAIL"
        CHECK_VALUES[firewall_policy]="No active firewall detected"
        CHECK_DETAILS[firewall_policy]="Install and configure a firewall (ufw, firewalld, iptables, or nftables)"
        echo 10
        return
    fi

    # Analyze firewall rules based on type
    case $firewall_type in
        ufw)
            local ufw_status=$(ufw status verbose 2>/dev/null)
            local default_in=$(echo "$ufw_status" | grep "Default:" | grep "deny (incoming)")
            local allow_rules=$(echo "$ufw_status" | grep -c "ALLOW")

            if [ -z "$default_in" ]; then
                issues="${issues}Default deny not set for incoming; "
                score=$((score - 30))
            fi

            if [ $allow_rules -eq 0 ]; then
                issues="${issues}No allow rules configured; "
                score=$((score - 20))
            fi
            ;;
        firewalld)
            local active_zones=$(firewall-cmd --get-active-zones 2>/dev/null)
            local default_zone=$(firewall-cmd --get-default-zone 2>/dev/null)

            if [ -z "$active_zones" ]; then
                issues="${issues}No active firewall zones; "
                score=$((score - 25))
            fi

            # Check if services are restricted
            local services=$(firewall-cmd --zone="$default_zone" --list-services 2>/dev/null)
            if echo "$services" | grep -q "ssh\|http\|https"; then
                # Some services allowed - check if too permissive
                if echo "$services" | grep -q "samba\|ftp\|telnet"; then
                    issues="${issues}Potentially insecure services allowed; "
                    score=$((score - 15))
                fi
            fi
            ;;
        iptables|nftables)
            # Check for basic INPUT chain policy
            local input_policy=""
            if [ "$firewall_type" = "iptables" ]; then
                input_policy=$(iptables -L INPUT -n | head -1 | awk '{print $4}')
            else
                # nftables - check for drop policy
                if nft list ruleset | grep -q "drop\|reject"; then
                    input_policy="DROP"
                fi
            fi

            if [ "$input_policy" != "DROP" ]; then
                issues="${issues}INPUT chain not default DROP; "
                score=$((score - 25))
            fi
            ;;
    esac

    # Check listening ports vs firewall rules
    local listening_ports=$(ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4}' | awk -F: '{print $NF}' | sort -u)
    local allowed_ports=""

    case $firewall_type in
        ufw)
            allowed_ports=$(ufw status | grep ALLOW | awk '{print $1}' | tr '\n' ' ')
            ;;
        firewalld)
            allowed_ports=$(firewall-cmd --list-ports --zone="$default_zone" 2>/dev/null | tr ' ' '\n' | awk -F/ '{print $1}' | tr '\n' ' ')
            ;;
    esac

    # Compare listening vs allowed (simplified check)
    local mismatch_found=false
    for port in $listening_ports; do
        if [[ $port =~ ^[0-9]+$ ]] && [ "$port" != "22" ] && [ "$port" != "80" ] && [ "$port" != "443" ]; then
            if ! echo "$allowed_ports" | grep -q "$port"; then
                mismatch_found=true
                break
            fi
        fi
    done

    if $mismatch_found; then
        issues="${issues}Potential mismatch between listening and allowed ports; "
        score=$((score - 10))
    fi

    if [ $score -ge 90 ]; then
        CHECK_RESULTS[firewall_policy]="PASS"
        CHECK_VALUES[firewall_policy]="Firewall active and configured ($firewall_type)"
    elif [ $score -ge 70 ]; then
        CHECK_RESULTS[firewall_policy]="WARN"
        CHECK_VALUES[firewall_policy]="Firewall active but needs review ($firewall_type)"
        CHECK_DETAILS[firewall_policy]="${issues% }"
    else
        CHECK_RESULTS[firewall_policy]="FAIL"
        CHECK_VALUES[firewall_policy]="Firewall configuration inadequate ($firewall_type)"
        CHECK_DETAILS[firewall_policy]="${issues% }"
    fi

    echo $score
}

check_kernel_hardening() {
    print_subsection "Kernel Hardening Check"

    local score=100
    local issues=""
    local details=""

    # Check key sysctl values
    local sysctl_checks=(
        "net.ipv4.ip_forward:0"
        "net.ipv4.conf.all.accept_redirects:0"
        "net.ipv4.conf.all.accept_source_route:0"
        "net.ipv4.conf.all.rp_filter:1"
        "net.ipv4.tcp_syncookies:1"
        "kernel.randomize_va_space:2"
        "kernel.kptr_restrict:1"
        "kernel.dmesg_restrict:1"
        "fs.suid_dumpable:0"
    )

    for check in "${sysctl_checks[@]}"; do
        local key=$(echo "$check" | cut -d: -f1)
        local expected=$(echo "$check" | cut -d: -f2)
        local actual=$(sysctl -n "$key" 2>/dev/null)

        if [ "$actual" != "$expected" ]; then
            issues="${issues}$key=$actual (expected $expected); "
            score=$((score - 5))
        fi
    done

    # Check for ASLR
    if [ ! -f /proc/sys/kernel/randomize_va_space ] || [ "$(cat /proc/sys/kernel/randomize_va_space)" != "2" ]; then
        issues="${issues}ASLR not fully enabled; "
        score=$((score - 10))
    fi

    # Check for core dumps
    if [ "$(sysctl -n fs.suid_dumpable)" != "0" ]; then
        issues="${issues}SUID core dumps enabled; "
        score=$((score - 10))
    fi

    if [ $score -ge 90 ]; then
        CHECK_RESULTS[kernel_hardening]="PASS"
        CHECK_VALUES[kernel_hardening]="Kernel properly hardened"
    elif [ $score -ge 70 ]; then
        CHECK_RESULTS[kernel_hardening]="WARN"
        CHECK_VALUES[kernel_hardening]="Kernel partially hardened"
        CHECK_DETAILS[kernel_hardening]="${issues% }"
    else
        CHECK_RESULTS[kernel_hardening]="FAIL"
        CHECK_VALUES[kernel_hardening]="Kernel hardening inadequate"
        CHECK_DETAILS[kernel_hardening]="${issues% }"
    fi

    echo $score
}

check_service_sandboxing() {
    print_subsection "Service Sandboxing Check"

    local score=100
    local issues=""
    local details=""

    # Check systemd services for hardening
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        local service_files=$(find /etc/systemd/system -name "*.service" -type f 2>/dev/null)
        local hardened_services=0
        local total_services=0

        for service_file in $service_files; do
            ((total_services++))
            local has_hardening=false

            # Check for key hardening directives
            if grep -q "NoNewPrivileges=" "$service_file" && grep -q "PrivateTmp=" "$service_file"; then
                has_hardening=true
                ((hardened_services++))
            fi

            # Check for additional security
            if grep -q "ProtectSystem=" "$service_file" || grep -q "ProtectHome=" "$service_file" || grep -q "CapabilityBoundingSet=" "$service_file"; then
                has_hardening=true
            fi
        done

        if [ $total_services -gt 0 ]; then
            local hardening_ratio=$((hardened_services * 100 / total_services))
            if [ $hardening_ratio -lt 50 ]; then
                issues="${issues}Only ${hardening_ratio}% services hardened ($hardened_services/$total_services); "
                score=$((score - 30))
            elif [ $hardening_ratio -lt 80 ]; then
                issues="${issues}Limited service hardening ($hardening_ratio%); "
                score=$((score - 15))
            fi
        fi
    else
        issues="${issues}Non-systemd service manager; "
        score=$((score - 20))
    fi

    if [ $score -ge 90 ]; then
        CHECK_RESULTS[service_sandboxing]="PASS"
        CHECK_VALUES[service_sandboxing]="Services properly sandboxed"
    elif [ $score -ge 70 ]; then
        CHECK_RESULTS[service_sandboxing]="WARN"
        CHECK_VALUES[service_sandboxing]="Service sandboxing partial"
        CHECK_DETAILS[service_sandboxing]="${issues% }"
    else
        CHECK_RESULTS[service_sandboxing]="FAIL"
        CHECK_VALUES[service_sandboxing]="Service sandboxing inadequate"
        CHECK_DETAILS[service_sandboxing]="${issues% }"
    fi

    echo $score
}

check_temp_directories() {
    print_subsection "Temporary Directories Check"

    local score=100
    local issues=""
    local details=""

    # Check /tmp permissions
    local tmp_perms=$(stat -c %a /tmp 2>/dev/null)
    if [ "$tmp_perms" != "1777" ]; then
        issues="${issues}/tmp permissions incorrect ($tmp_perms); "
        score=$((score - 15))
    fi

    # Check /var/tmp permissions
    local vartmp_perms=$(stat -c %a /var/tmp 2>/dev/null)
    if [ "$vartmp_perms" != "1777" ]; then
        issues="${issues}/var/tmp permissions incorrect ($vartmp_perms); "
        score=$((score - 15))
    fi

    # Check for world-writable files in temp dirs
    local world_writable_tmp=$(find /tmp /var/tmp -type f -perm -002 2>/dev/null | wc -l)
    if [ $world_writable_tmp -gt 0 ]; then
        issues="${issues}$world_writable_tmp world-writable files in temp dirs; "
        score=$((score - 20))
    fi

    # Check for executable content in temp
    local executable_temp=$(find /tmp /var/tmp -type f -executable 2>/dev/null | wc -l)
    if [ $executable_temp -gt 5 ]; then
        issues="${issues}High number of executables in temp ($executable_temp); "
        score=$((score - 15))
    fi

    # Check for suspicious files
    local suspicious_files=$(find /tmp /var/tmp -name "*.sh" -o -name "*.py" -o -name "*.pl" 2>/dev/null | wc -l)
    if [ $suspicious_files -gt 2 ]; then
        issues="${issues}Suspicious scripts in temp dirs ($suspicious_files); "
        score=$((score - 10))
    fi

    if [ $score -ge 90 ]; then
        CHECK_RESULTS[temp_directories]="PASS"
        CHECK_VALUES[temp_directories]="Temp directories secure"
    elif [ $score -ge 70 ]; then
        CHECK_RESULTS[temp_directories]="WARN"
        CHECK_VALUES[temp_directories]="Temp directories need attention"
        CHECK_DETAILS[temp_directories]="${issues% }"
    else
        CHECK_RESULTS[temp_directories]="FAIL"
        CHECK_VALUES[temp_directories]="Temp directories vulnerable"
        CHECK_DETAILS[temp_directories]="${issues% }"
    fi

    echo $score
}

execute_check() {
    local check_name=$1
    local check_func=$2
    local weight=$3

    ((COMPLETED_CHECKS++))

    local score
    $check_func > /tmp/security_check_output.txt 2>&1
    score=$(tail -1 /tmp/security_check_output.txt)

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
    echo '║                   SECURITY AUDIT REPORT                         ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${RESET}"

    local end_time=$(date +%s)
    local duration=$((end_time - SCRIPT_START_TIME))

    print_metric "Scan Duration" "${duration}s"
    print_metric "Total Security Checks" "$TOTAL_CHECKS"
    print_metric "OS Distribution" "${OS_DISTRO^} $OS_VERSION"
    print_metric "Package Manager" "$PACKAGE_MANAGER"
    print_metric "Scan Timestamp" "$(date '+%Y-%m-%d %H:%M:%S %Z')"

    echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}DETAILED SECURITY CATEGORY RESULTS:${RESET}"
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
               echo -e "    ${YELLOW}Issues:${RESET} ${CHECK_DETAILS[$category]}"
            fi
        fi

        case $result in
            PASS) ((pass_count++)) ;;
            WARN) ((warn_count++)) ;;
            FAIL) ((fail_count++)) ;;
        esac
    done

    echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════${RESET}"

    local final_status="SECURE"
    local status_color=$GREEN

    if [ $fail_count -gt 0 ]; then
        final_status="CRITICAL"
        status_color=$RED
    elif [ $warn_count -gt 0 ]; then
        final_status="WARNING"
        status_color=$YELLOW
    fi

    echo -e "\n${BOLD}SECURITY METRICS:${RESET}"
    echo -e "  ${BOLD}Overall Security Score:${RESET} ${status_color}${OVERALL_SCORE}/100${RESET}"
    echo -e "  ${BOLD}Security Status:${RESET} $(severity_badge $final_status)"

    echo -e "\n${BOLD}SECURITY CHECK SUMMARY:${RESET}"
    echo -e "  ${GREEN}✓ Passed Checks:${RESET}   $pass_count"
    echo -e "  ${YELLOW}⚠ Warning Checks:${RESET}  $warn_count"
    echo -e "  ${RED}✗ Failed Checks:${RESET}   $fail_count"
    echo -e "  ${BLUE}ℹ Total Checks:${RESET}    $TOTAL_CHECKS"

    local pass_percentage=$((pass_count * 100 / TOTAL_CHECKS))
    echo -e "\n${BOLD}Security Compliance Rate:${RESET} ${GREEN}${pass_percentage}%${RESET}"

    echo -e "\n${CYAN}${BOLD}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║                  SECURITY RECOMMENDATIONS                       ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${RESET}"

    if [ $fail_count -gt 0 ]; then
        echo -e "\n${RED}${BOLD}⚡ CRITICAL SECURITY VULNERABILITIES DETECTED${RESET}"
        echo -e "    ${RED}• Immediate security hardening required for ${fail_count} failed check(s)${RESET}"
        echo -e "    ${RED}• System may be exposed to attacks${RESET}"
        echo -e "    ${RED}• Address critical issues immediately${RESET}"
    fi

    if [ $warn_count -gt 0 ]; then
        echo -e "\n${YELLOW}${BOLD}⚠️  SECURITY IMPROVEMENTS NEEDED${RESET}"
        echo -e "    ${YELLOW}• ${warn_count} security warning(s) require attention${RESET}"
        echo -e "    ${YELLOW}• Review and implement security best practices${RESET}"
        echo -e "    ${YELLOW}• Consider security hardening within 24 hours${RESET}"
    fi

    if [ $fail_count -eq 0 ] && [ $warn_count -eq 0 ]; then
        echo -e "\n${GREEN}${BOLD}✓ SYSTEM SECURITY COMPLIANT${RESET}"
        echo -e "    ${GREEN}• All security checks passed${RESET}"
        echo -e "    ${GREEN}• System follows security best practices${RESET}"
        echo -e "    ${GREEN}• Continue regular security monitoring${RESET}"
    fi

    # Specific recommendations
    if [ "${CHECK_RESULTS[ssh_hardening]}" = "FAIL" ]; then
        echo -e "    ${RED}→ Harden SSH configuration: disable root login, enforce key auth, set timeouts${RESET}"
    fi

    if [ "${CHECK_RESULTS[privilege_escalation]}" = "FAIL" ]; then
        echo -e "    ${RED}→ Review sudoers: remove NOPASSWD, limit ALL permissions, enable env_reset${RESET}"
    fi

    if [ "${CHECK_RESULTS[brute_force_protection]}" = "FAIL" ]; then
        echo -e "    ${RED}→ Configure PAM faillock: set deny count, fail interval, unlock time${RESET}"
    fi

    if [ "${CHECK_RESULTS[mandatory_access_control]}" = "FAIL" ]; then
        echo -e "    ${RED}→ Enable MAC: SELinux enforcing or AppArmor profiles${RESET}"
    fi

    if [ "${CHECK_RESULTS[audit_coverage]}" = "FAIL" ]; then
        echo -e "    ${RED}→ Configure auditd: add comprehensive rules, ensure service is running${RESET}"
    fi

    if [ "${CHECK_RESULTS[file_integrity]}" = "FAIL" ]; then
        echo -e "    ${RED}→ Install and configure AIDE: initialize database, schedule regular checks${RESET}"
    fi

    if [ "${CHECK_RESULTS[firewall_policy]}" = "FAIL" ]; then
        echo -e "    ${RED}→ Configure firewall: set default deny, allow only necessary ports${RESET}"
    fi

    if [ "${CHECK_RESULTS[kernel_hardening]}" = "FAIL" ]; then
        echo -e "    ${RED}→ Harden kernel: configure sysctl values for network and security${RESET}"
    fi

    if [ "${CHECK_RESULTS[service_sandboxing]}" = "FAIL" ]; then
        echo -e "    ${RED}→ Sandbox services: add systemd security directives${RESET}"
    fi

    if [ "${CHECK_RESULTS[temp_directories]}" = "FAIL" ]; then
        echo -e "    ${RED}→ Secure temp directories: fix permissions, remove suspicious files${RESET}"
    fi

    echo -e "\n${DIM}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${DIM}Security Audit Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
    echo -e "${DIM}═══════════════════════════════════════════════════════════════${RESET}\n"
}

main() {
    init_thresholds
    detect_distro

    CHECK_ORDER=("ssh_hardening" "privilege_escalation" "brute_force_protection" "mandatory_access_control" "audit_coverage" "file_integrity" "firewall_policy" "kernel_hardening" "service_sandboxing" "temp_directories")
    TOTAL_CHECKS=${#CHECK_ORDER[@]}

    print_header

    print_section "SYSTEM SECURITY AUDIT"

    execute_check "SSH Hardening" check_ssh_hardening ${CHECK_WEIGHTS[ssh_hardening]}
    execute_check "Privilege Escalation" check_privilege_escalation ${CHECK_WEIGHTS[privilege_escalation]}
    execute_check "Brute Force Protection" check_brute_force_protection ${CHECK_WEIGHTS[brute_force_protection]}
    execute_check "Mandatory Access Control" check_mandatory_access_control ${CHECK_WEIGHTS[mandatory_access_control]}
    execute_check "Audit Coverage" check_audit_coverage ${CHECK_WEIGHTS[audit_coverage]}
    execute_check "File Integrity" check_file_integrity ${CHECK_WEIGHTS[file_integrity]}
    execute_check "Firewall Policy" check_firewall_policy ${CHECK_WEIGHTS[firewall_policy]}
    execute_check "Kernel Hardening" check_kernel_hardening ${CHECK_WEIGHTS[kernel_hardening]}
    execute_check "Service Sandboxing" check_service_sandboxing ${CHECK_WEIGHTS[service_sandboxing]}
    execute_check "Temp Directories" check_temp_directories ${CHECK_WEIGHTS[temp_directories]}

    print_summary

    if load_telegram_config; then
        echo -e "\n${CYAN}Sending security report to Telegram...${RESET}"
        local telegram_message="<b>System Security Audit Report</b>%0A"
        telegram_message+="<b>Status:</b> $([ "${fail_count:-0}" -gt 0 ] && echo "CRITICAL" || ([ "${warn_count:-0}" -gt 0 ] && echo "WARNING" || echo "SECURE"))%0A"
        telegram_message+="<b>Score:</b> ${OVERALL_SCORE}/100%0A"
        telegram_message+="<b>Passed:</b> ${pass_count:-0} | <b>Warnings:</b> ${warn_count:-0} | <b>Failed:</b> ${fail_count:-0}%0A"
        telegram_message+="<b>Host:</b> $(hostname)%0A"
        telegram_message+="<b>Time:</b> $(date '+%Y-%m-%d %H:%M:%S %Z')"
        
        if send_telegram_message "$telegram_message"; then
            echo -e "${GREEN}Security report sent to Telegram successfully!${RESET}"
        else
            echo -e "${RED}Failed to send security report to Telegram. Check bot token and chat ID.${RESET}"
        fi
    else
        echo -e "\n${YELLOW}⚠ Telegram configuration not found. Skipping Telegram notification.${RESET}"
        echo -e "${DIM}To enable Telegram notifications, create /etc/system_scripts/auth.conf with:${RESET}"
        echo -e "${DIM}  TELEGRAM_BOT_TOKEN=\"your_bot_token\"${RESET}"
        echo -e "${DIM}  TELEGRAM_CHAT_ID=\"your_chat_id\"${RESET}"
    fi
}

main "$@"
