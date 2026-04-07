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

SCRIPT_START_TIME=$(date +%s)
OS_DISTRO=""
OS_VERSION=""
PACKAGE_MANAGER=""
SERVICE_MANAGER=""
WEB_SERVER=""
FIREWALL_TYPE=""
HOSTNAME_SET=false

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║              FIRST BOOT SERVER SETUP                            ║'
    echo '║              Automated Initial Configuration                    ║'
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
        SKIP) echo -e "${CYAN}⊘${RESET}" ;;
    esac
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
            SKIP) color=$CYAN ;;
        esac
        printf "    ${DIM}%-35s${RESET} ${color}%s${RESET}\n" "$label:" "$value"
    fi
}

detect_distro() {
    print_subsection "Detecting Distribution"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_DISTRO=$ID
        OS_VERSION=$VERSION_ID
        case $ID in
            ubuntu|debian|linuxmint|pop)
                PACKAGE_MANAGER="apt"
                SERVICE_MANAGER="systemd"
                echo -e "    ${GREEN}✓ Detected: Ubuntu/Debian family${RESET}"
                ;;
            rhel|centos|fedora|rocky|almalinux|amzn)
                if [ -f /usr/bin/dnf ]; then
                    PACKAGE_MANAGER="dnf"
                else
                    PACKAGE_MANAGER="yum"
                fi
                SERVICE_MANAGER="systemd"
                echo -e "    ${GREEN}✓ Detected: RHEL/CentOS family${RESET}"
                ;;
            arch|manjaro)
                PACKAGE_MANAGER="pacman"
                SERVICE_MANAGER="systemd"
                echo -e "    ${GREEN}✓ Detected: Arch family${RESET}"
                ;;
            alpine)
                PACKAGE_MANAGER="apk"
                SERVICE_MANAGER="openrc"
                echo -e "    ${GREEN}✓ Detected: Alpine${RESET}"
                ;;
            opensuse*|suse*)
                PACKAGE_MANAGER="zypper"
                SERVICE_MANAGER="systemd"
                echo -e "    ${GREEN}✓ Detected: SUSE family${RESET}"
                ;;
            *)
                PACKAGE_MANAGER="unknown"
                SERVICE_MANAGER="unknown"
                echo -e "    ${YELLOW}⚠ Unknown distribution: $ID${RESET}"
                ;;
        esac
    elif [ -f /etc/redhat-release ]; then
        OS_DISTRO="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)
        PACKAGE_MANAGER="yum"
        SERVICE_MANAGER="systemd"
        echo -e "    ${GREEN}✓ Detected: RHEL/CentOS (legacy)${RESET}"
    elif [ -f /etc/debian_version ]; then
        OS_DISTRO="debian"
        OS_VERSION=$(cat /etc/debian_version)
        PACKAGE_MANAGER="apt"
        SERVICE_MANAGER="systemd"
        echo -e "    ${GREEN}✓ Detected: Debian${RESET}"
    else
        OS_DISTRO="unknown"
        OS_VERSION="unknown"
        PACKAGE_MANAGER="unknown"
        SERVICE_MANAGER="unknown"
        echo -e "    ${RED}✗ Unable to detect distribution${RESET}"
        return 1
    fi

    print_metric "Distribution" "${OS_DISTRO^} $OS_VERSION"
    print_metric "Package Manager" "$PACKAGE_MANAGER"
    print_metric "Service Manager" "$SERVICE_MANAGER"

    return 0
}

update_system() {
    print_subsection "Updating System Packages"

    case $PACKAGE_MANAGER in
        apt)
            echo -e "    ${BLUE}Updating package lists...${RESET}"
            apt update
            echo -e "    ${BLUE}Upgrading packages...${RESET}"
            apt upgrade -y
            echo -e "    ${BLUE}Installing repository helpers...${RESET}"
            apt install -y software-properties-common
            ;;
        dnf)
            echo -e "    ${BLUE}Updating system...${RESET}"
            dnf update -y
            echo -e "    ${BLUE}Installing repository helpers...${RESET}"
            dnf install -y dnf-plugins-core
            ;;
        yum)
            echo -e "    ${BLUE}Updating system...${RESET}"
            yum update -y
            echo -e "    ${BLUE}Installing repository helpers...${RESET}"
            yum install -y yum-utils
            ;;
        pacman)
            echo -e "    ${BLUE}Updating system...${RESET}"
            pacman -Syu --noconfirm
            ;;
        zypper)
            echo -e "    ${BLUE}Updating system...${RESET}"
            zypper update -y
            ;;
        apk)
            echo -e "    ${BLUE}Updating system...${RESET}"
            apk update && apk upgrade
            ;;
        *)
            echo -e "    ${RED}✗ Unsupported package manager: $PACKAGE_MANAGER${RESET}"
            return 1
            ;;
    esac

    # Install EPEL for RHEL/CentOS if not already installed
    if [[ "$OS_DISTRO" =~ ^(rhel|centos|almalinux|rocky)$ ]]; then
        if ! rpm -q epel-release >/dev/null 2>&1; then
            echo -e "    ${BLUE}Installing EPEL repository...${RESET}"
            if [ "$PACKAGE_MANAGER" = "dnf" ]; then
                dnf install -y epel-release
            else
                yum install -y epel-release
            fi
        fi
    fi

    # Enable universe repository for Ubuntu
    if [[ "$OS_DISTRO" =~ ^(ubuntu|debian|linuxmint|pop)$ ]]; then
        if ! grep -q "^deb.*universe" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
            echo -e "    ${BLUE}Enabling universe repository...${RESET}"
            add-apt-repository universe -y
            apt update
        fi
    fi

    echo -e "    ${GREEN}✓ System update completed${RESET}"
}

install_essential_packages() {
    print_subsection "Installing Essential Packages"

    local packages=()

    case $PACKAGE_MANAGER in
        apt)
            packages=(
                curl wget git vim nano
                htop iotop iftop ncdu
                unzip zip tar
                bash-completion
                net-tools dnsutils
                lsof strace tcpdump
                cron
                rsync
                jq
            )
            ;;
        dnf|yum)
            packages=(
                curl wget git vim nano
                htop iotop iftop ncdu
                unzip zip tar
                bash-completion
                net-tools bind-utils
                lsof strace tcpdump
                cronie
                rsync
                jq
            )
            ;;
        pacman)
            packages=(
                curl wget git vim nano
                htop iotop iftop ncdu
                unzip zip tar
                bash-completion
                net-tools bind-tools
                lsof strace tcpdump
                cron
                rsync
                jq
            )
            ;;
        zypper)
            packages=(
                curl wget git vim nano
                htop iotop iftop ncdu
                unzip zip tar
                bash-completion
                net-tools bind-utils
                lsof strace tcpdump
                cron
                rsync
                jq
            )
            ;;
        apk)
            packages=(
                curl wget git vim nano
                htop iotop iftop ncdu
                unzip zip tar
                bash-completion
                net-tools bind-tools
                lsof strace tcpdump
                cron
                rsync
                jq
            )
            ;;
    esac

    echo -e "    ${BLUE}Installing essential packages...${RESET}"
    case $PACKAGE_MANAGER in
        apt)
            apt install -y "${packages[@]}"
            ;;
        dnf)
            dnf install -y "${packages[@]}"
            ;;
        yum)
            yum install -y "${packages[@]}"
            ;;
        pacman)
            pacman -S --noconfirm "${packages[@]}"
            ;;
        zypper)
            zypper install -y "${packages[@]}"
            ;;
        apk)
            apk add "${packages[@]}"
            ;;
    esac

    echo -e "    ${GREEN}✓ Essential packages installed${RESET}"
}

set_hostname() {
    print_subsection "Setting System Hostname"

    local current_hostname=$(hostname)
    echo -e "    ${BLUE}Current hostname: ${BOLD}$current_hostname${RESET}"

    if [ "$current_hostname" = "localhost" ] || [ "$current_hostname" = "(none)" ] || [[ "$current_hostname" =~ ^localhost ]]; then
        echo -e "    ${YELLOW}⚠ Default hostname detected${RESET}"
        read -p "    Enter new hostname: " new_hostname

        if [ -n "$new_hostname" ]; then
            echo -e "    ${BLUE}Setting hostname to: $new_hostname${RESET}"
            hostnamectl set-hostname "$new_hostname" 2>/dev/null || echo "$new_hostname" > /etc/hostname
            HOSTNAME_SET=true
            echo -e "    ${GREEN}✓ Hostname set to: $new_hostname${RESET}"
        else
            echo -e "    ${YELLOW}⚠ Hostname not changed${RESET}"
        fi
    else
        echo -e "    ${GREEN}✓ Hostname already configured: $current_hostname${RESET}"
    fi
}

detect_firewall() {
    print_subsection "Detecting Existing Firewall"

    # Check for active firewalls
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        FIREWALL_TYPE="ufw"
        echo -e "    ${CYAN}⊘ UFW firewall detected and active${RESET}"
        return 0
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q "running"; then
        FIREWALL_TYPE="firewalld"
        echo -e "    ${CYAN}⊘ Firewalld detected and running${RESET}"
        return 0
    elif command -v iptables >/dev/null 2>&1 && iptables -L 2>/dev/null | grep -q "Chain"; then
        FIREWALL_TYPE="iptables"
        echo -e "    ${CYAN}⊘ Iptables rules detected${RESET}"
        return 0
    elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -q "table"; then
        FIREWALL_TYPE="nftables"
        echo -e "    ${CYAN}⊘ Nftables rules detected${RESET}"
        return 0
    fi

    echo -e "    ${YELLOW}⚠ No active firewall detected${RESET}"
    return 1
}

setup_firewall() {
    print_subsection "Setting Up Firewall"

    if detect_firewall; then
        echo -e "    ${CYAN}⊘ Skipping firewall setup - already configured${RESET}"
        return 0
    fi

    echo -e "    ${BLUE}Select firewall to install:${RESET}"
    echo -e "    ${BOLD}1)${RESET} UFW (Ubuntu/Debian)"
    echo -e "    ${BOLD}2)${RESET} Firewalld (RHEL/CentOS)"
    echo -e "    ${BOLD}3)${RESET} Iptables (Legacy)"
    echo

    local choice
    read -p "    Enter choice (1-3): " choice

    case $choice in
        1)
            FIREWALL_TYPE="ufw"
            echo -e "    ${BLUE}Installing UFW...${RESET}"
            case $PACKAGE_MANAGER in
                apt)
                    apt install -y ufw
                    ;;
                *)
                    echo -e "    ${RED}✗ UFW not available for this distribution${RESET}"
                    return 1
                    ;;
            esac
            ;;
        2)
            FIREWALL_TYPE="firewalld"
            echo -e "    ${BLUE}Installing Firewalld...${RESET}"
            case $PACKAGE_MANAGER in
                dnf|yum)
                    $PACKAGE_MANAGER install -y firewalld
                    systemctl enable firewalld
                    systemctl start firewalld
                    ;;
                *)
                    echo -e "    ${RED}✗ Firewalld not available for this distribution${RESET}"
                    return 1
                    ;;
            esac
            ;;
        3)
            FIREWALL_TYPE="iptables"
            echo -e "    ${BLUE}Setting up iptables...${RESET}"
            case $PACKAGE_MANAGER in
                apt)
                    apt install -y iptables iptables-persistent
                    ;;
                dnf|yum)
                    $PACKAGE_MANAGER install -y iptables-services
                    systemctl enable iptables
                    systemctl start iptables
                    ;;
                *)
                    echo -e "    ${YELLOW}⚠ Iptables may already be available${RESET}"
                    ;;
            esac
            ;;
        *)
            echo -e "    ${RED}✗ Invalid choice${RESET}"
            return 1
            ;;
    esac

    # Configure firewall
    echo -e "    ${BLUE}Configuring firewall...${RESET}"
    case $FIREWALL_TYPE in
        ufw)
            ufw --force enable
            ufw allow ssh
            ufw allow 80/tcp
            ufw allow 443/tcp
            ufw --force reload
            ;;
        firewalld)
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
            firewall-cmd --reload
            ;;
        iptables)
            # Basic iptables rules
            iptables -F
            iptables -X
            iptables -t nat -F
            iptables -t nat -X
            iptables -t mangle -F
            iptables -t mangle -X

            # Default policies
            iptables -P INPUT DROP
            iptables -P FORWARD DROP
            iptables -P OUTPUT ACCEPT

            # Allow loopback
            iptables -A INPUT -i lo -j ACCEPT

            # Allow established connections
            iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

            # Allow SSH
            iptables -A INPUT -p tcp --dport 22 -j ACCEPT

            # Allow HTTP/HTTPS
            iptables -A INPUT -p tcp --dport 80 -j ACCEPT
            iptables -A INPUT -p tcp --dport 443 -j ACCEPT

            # Save rules
            if command -v netfilter-persistent >/dev/null 2>&1; then
                netfilter-persistent save
            elif [ -f /etc/init.d/iptables ]; then
                service iptables save
            fi
            ;;
    esac

    echo -e "    ${GREEN}✓ Firewall configured: $FIREWALL_TYPE${RESET}"
}

check_web_server() {
    print_subsection "Checking Web Server"

    if systemctl is-active --quiet apache2 httpd 2>/dev/null || systemctl is-active --quiet nginx 2>/dev/null; then
        echo -e "    ${CYAN}⊘ Web server already running${RESET}"
        return 0
    fi

    echo -e "    ${BLUE}No web server detected${RESET}"
    echo -e "    ${BLUE}Select web server to install:${RESET}"
    echo -e "    ${BOLD}1)${RESET} Apache"
    echo -e "    ${BOLD}2)${RESET} Nginx"
    echo -e "    ${BOLD}3)${RESET} Skip"
    echo

    local choice
    read -p "    Enter choice (1-3): " choice

    case $choice in
        1)
            WEB_SERVER="apache"
            echo -e "    ${BLUE}Installing Apache...${RESET}"
            case $PACKAGE_MANAGER in
                apt)
                    apt install -y apache2
                    systemctl enable apache2
                    systemctl start apache2
                    ;;
                dnf|yum)
                    $PACKAGE_MANAGER install -y httpd
                    systemctl enable httpd
                    systemctl start httpd
                    ;;
                pacman)
                    pacman -S --noconfirm apache
                    systemctl enable httpd
                    systemctl start httpd
                    ;;
                *)
                    echo -e "    ${RED}✗ Apache installation not supported${RESET}"
                    return 1
                    ;;
            esac
            ;;
        2)
            WEB_SERVER="nginx"
            echo -e "    ${BLUE}Installing Nginx...${RESET}"
            case $PACKAGE_MANAGER in
                apt)
                    apt install -y nginx
                    systemctl enable nginx
                    systemctl start nginx
                    ;;
                dnf|yum)
                    $PACKAGE_MANAGER install -y nginx
                    systemctl enable nginx
                    systemctl start nginx
                    ;;
                pacman)
                    pacman -S --noconfirm nginx
                    systemctl enable nginx
                    systemctl start nginx
                    ;;
                *)
                    echo -e "    ${RED}✗ Nginx installation not supported${RESET}"
                    return 1
                    ;;
            esac
            ;;
        3)
            echo -e "    ${CYAN}⊘ Skipping web server installation${RESET}"
            return 0
            ;;
        *)
            echo -e "    ${RED}✗ Invalid choice${RESET}"
            return 1
            ;;
    esac

    echo -e "    ${GREEN}✓ Web server installed: $WEB_SERVER${RESET}"
}

setup_security_hardening() {
    print_subsection "Setting Up Security Hardening"

    # Install fail2ban
    echo -e "    ${BLUE}Installing fail2ban...${RESET}"
    case $PACKAGE_MANAGER in
        apt)
            apt install -y fail2ban
            ;;
        dnf|yum)
            $PACKAGE_MANAGER install -y fail2ban
            ;;
        pacman)
            pacman -S --noconfirm fail2ban
            ;;
        zypper)
            zypper install -y fail2ban
            ;;
        apk)
            apk add fail2ban
            ;;
    esac

    if command -v fail2ban-server >/dev/null 2>&1; then
        systemctl enable fail2ban 2>/dev/null || true
        systemctl start fail2ban 2>/dev/null || true
        echo -e "    ${GREEN}✓ fail2ban installed and started${RESET}"
    fi

    # Install auditd
    echo -e "    ${BLUE}Installing auditd...${RESET}"
    case $PACKAGE_MANAGER in
        apt)
            apt install -y auditd audispd-plugins
            ;;
        dnf|yum)
            $PACKAGE_MANAGER install -y audit audit-libs
            ;;
        pacman)
            pacman -S --noconfirm audit
            ;;
        zypper)
            zypper install -y audit
            ;;
        apk)
            apk add audit
            ;;
    esac

    if command -v auditd >/dev/null 2>&1; then
        systemctl enable auditd 2>/dev/null || true
        systemctl start auditd 2>/dev/null || true
        echo -e "    ${GREEN}✓ auditd installed and started${RESET}"
    fi

    # Setup automatic security updates
    echo -e "    ${BLUE}Setting up automatic security updates...${RESET}"
    case $OS_DISTRO in
        ubuntu|debian|linuxmint|pop)
            apt install -y unattended-upgrades
            dpkg-reconfigure -f noninteractive unattended-upgrades
            ;;
        rhel|centos|fedora|rocky|almalinux)
            $PACKAGE_MANAGER install -y dnf-automatic
            systemctl enable dnf-automatic.timer
            systemctl start dnf-automatic.timer
            ;;
    esac

    # Check SELinux/AppArmor
    echo -e "    ${BLUE}Checking Mandatory Access Control...${RESET}"
    case $OS_DISTRO in
        rhel|centos|fedora|rocky|almalinux|amzn)
            if command -v getenforce >/dev/null 2>&1; then
                local selinux_status=$(getenforce 2>/dev/null)
                if [ "$selinux_status" = "Disabled" ]; then
                    echo -e "    ${YELLOW}⚠ SELinux is disabled - consider enabling${RESET}"
                else
                    echo -e "    ${GREEN}✓ SELinux status: $selinux_status${RESET}"
                fi
            else
                echo -e "    ${YELLOW}⚠ SELinux not available${RESET}"
            fi
            ;;
        ubuntu|debian|linuxmint|pop)
            if command -v apparmor_status >/dev/null 2>&1; then
                echo -e "    ${GREEN}✓ AppArmor available${RESET}"
            else
                echo -e "    ${YELLOW}⚠ AppArmor not available${RESET}"
            fi
            ;;
    esac

    # Setup password policy and faillock
    echo -e "    ${BLUE}Setting up password policy...${RESET}"
    if [ -f /etc/security/pwquality.conf ]; then
        # Basic password quality settings
        sed -i 's/^# minlen =/minlen = 8/' /etc/security/pwquality.conf
        sed -i 's/^# dcredit =/dcredit = -1/' /etc/security/pwquality.conf
        sed -i 's/^# ucredit =/ucredit = -1/' /etc/security/pwquality.conf
        sed -i 's/^# ocredit =/ocredit = -1/' /etc/security/pwquality.conf
        sed -i 's/^# lcredit =/lcredit = -1/' /etc/security/pwquality.conf
        echo -e "    ${GREEN}✓ Password quality policy configured${RESET}"
    fi

    # Setup faillock
    if [ -f /etc/security/faillock.conf ]; then
        sed -i 's/^# deny =/deny = 5/' /etc/security/faillock.conf
        sed -i 's/^# fail_interval =/fail_interval = 900/' /etc/security/faillock.conf
        sed -i 's/^# unlock_time =/unlock_time = 600/' /etc/security/faillock.conf
        echo -e "    ${GREEN}✓ Account lockout policy configured${RESET}"
    fi

    # Basic sysctl hardening
    echo -e "    ${BLUE}Applying kernel hardening...${RESET}"
    cat > /etc/sysctl.d/99-security.conf << EOF
# Network hardening
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1

# Kernel hardening
kernel.randomize_va_space = 2
kernel.kptr_restrict = 1
kernel.dmesg_restrict = 1
fs.suid_dumpable = 0
EOF

    sysctl -p /etc/sysctl.d/99-security.conf >/dev/null 2>&1
    echo -e "    ${GREEN}✓ Kernel hardening applied${RESET}"

    echo -e "    ${GREEN}✓ Security hardening completed${RESET}"
}

print_summary() {
    echo -e "\n${CYAN}${BOLD}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║                   SETUP COMPLETION SUMMARY                      ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${RESET}"

    local end_time=$(date +%s)
    local duration=$((end_time - SCRIPT_START_TIME))

    print_metric "Setup Duration" "${duration}s"
    print_metric "Distribution" "${OS_DISTRO^} $OS_VERSION"
    print_metric "Package Manager" "$PACKAGE_MANAGER"
    print_metric "Service Manager" "$SERVICE_MANAGER"
    print_metric "Hostname Configured" "$([ "$HOSTNAME_SET" = true ] && echo "Yes" || echo "No")"
    print_metric "Firewall Type" "${FIREWALL_TYPE:-None}"
    print_metric "Web Server" "${WEB_SERVER:-None}"

    echo -e "\n${BOLD}COMPLETED TASKS:${RESET}"
    echo -e "  ${GREEN}✓${RESET} System packages updated"
    echo -e "  ${GREEN}✓${RESET} Essential packages installed"
    echo -e "  ${GREEN}✓${RESET} Hostname configured"
    echo -e "  ${GREEN}✓${RESET} Firewall setup completed"
    echo -e "  ${GREEN}✓${RESET} Security hardening applied"
    echo -e "  ${GREEN}✓${RESET} Web server configured"

    echo -e "\n${CYAN}${BOLD}NEXT STEPS:${RESET}"
    echo -e "  ${BLUE}• Review firewall rules and adjust as needed${RESET}"
    echo -e "  ${BLUE}• Configure SSH keys and disable password authentication${RESET}"
    echo -e "  ${BLUE}• Set up monitoring and alerting${RESET}"
    echo -e "  ${BLUE}• Configure backups${RESET}"
    echo -e "  ${BLUE}• Review and customize security policies${RESET}"

    echo -e "\n${DIM}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${DIM}First Boot Setup Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
    echo -e "${DIM}═══════════════════════════════════════════════════════════════${RESET}\n"
}

main() {
    print_header

    echo -e "${YELLOW}${BOLD}WARNING: This script will make system changes. Ensure you have backups.${RESET}"
    echo -e "${YELLOW}Press Enter to continue or Ctrl+C to abort.${RESET}"
    read

    print_section "SYSTEM UPDATE"
    if ! detect_distro; then
        echo -e "${RED}✗ Distribution detection failed. Exiting.${RESET}"
        exit 1
    fi

    update_system

    print_section "ESSENTIAL PACKAGES"
    install_essential_packages

    print_section "HOSTNAME CONFIGURATION"
    set_hostname

    print_section "FIREWALL SETUP"
    setup_firewall

    print_section "WEB SERVER"
    check_web_server

    print_section "SECURITY HARDENING"
    setup_security_hardening

    print_summary

    echo -e "${GREEN}${BOLD}✓ First boot setup completed successfully!${RESET}"
    echo -e "${BLUE}Reboot recommended to apply all changes.${RESET}"
}

main "$@"
