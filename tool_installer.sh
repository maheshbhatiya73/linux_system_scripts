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
DRY_RUN=false
LOG_FILE="/var/log/tool_installer_$(date +%Y%m%d_%H%M%S).log"
SELECTED_GROUPS=()
INSTALLED_PACKAGES=()

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    if [ "$level" = "ERROR" ]; then
        echo -e "${RED}[$level]${RESET} $message" >&2
    elif [ "$level" = "WARN" ]; then
        echo -e "${YELLOW}[$level]${RESET} $message" >&2
    elif [ "$level" = "INFO" ]; then
        echo -e "${BLUE}[$level]${RESET} $message"
    fi
}

print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║              TOOL INSTALLER                                     ║'
    echo '║              Automated Package Group Installer                  ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${RESET}"
    echo -e "${DIM}Started: $(date '+%Y-%m-%d %H:%M:%S') | Host: $(hostname) | User: $(whoami)${RESET}"
    echo -e "${DIM}Log file: $LOG_FILE${RESET}"
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
                log "INFO" "Detected Ubuntu/Debian family: $ID $VERSION_ID"
                ;;
            rhel|centos|fedora|rocky|almalinux|amzn)
                if [ -f /usr/bin/dnf ]; then
                    PACKAGE_MANAGER="dnf"
                else
                    PACKAGE_MANAGER="yum"
                fi
                log "INFO" "Detected RHEL family: $ID $VERSION_ID"
                ;;
            *)
                log "ERROR" "Unsupported distribution: $ID"
                echo -e "    ${RED}✗ Unsupported distribution: $ID${RESET}"
                echo -e "    ${YELLOW}Supported: Ubuntu/Debian, RHEL/Rocky/Alma/Fedora${RESET}"
                exit 1
                ;;
        esac
    else
        log "ERROR" "Cannot detect distribution - /etc/os-release not found"
        echo -e "    ${RED}✗ Cannot detect distribution${RESET}"
        exit 1
    fi

    print_metric "Distribution" "${OS_DISTRO^} $OS_VERSION"
    print_metric "Package Manager" "$PACKAGE_MANAGER"
    log "INFO" "Package manager: $PACKAGE_MANAGER"
}

define_package_groups() {
    # Programming Languages
    declare -gA PROGRAMMING_PACKAGES
    case $PACKAGE_MANAGER in
        apt)
            PROGRAMMING_PACKAGES=(
                [python3]="python3 python3-venv python3-dev"
                [python3-pip]="python3-pip"
                [ansible]="ansible"
                [make]="make"
                [gcc]="gcc g++ build-essential"
                [git]="git"
                [docker]="docker.io docker-compose"
                [golang]="golang-go"
                [rust]="rustc cargo"
                [nodejs]="nodejs npm"
                [cpp]="g++ clang"
            )
            ;;
        dnf|yum)
            PROGRAMMING_PACKAGES=(
                [python3]="python3 python3-pip python3-devel"
                [python3-pip]="python3-pip"
                [ansible]="ansible"
                [make]="make"
                [gcc]="gcc gcc-c++"
                [git]="git"
                [docker]="docker docker-compose"
                [golang]="golang"
                [rust]="rust cargo"
                [nodejs]="nodejs npm"
                [cpp]="gcc-c++ clang"
            )
            ;;
    esac

    # Web Stack
    declare -gA WEB_PACKAGES
    case $PACKAGE_MANAGER in
        apt)
            WEB_PACKAGES=(
                [nginx]="nginx"
                [apache2]="apache2"
                [certbot]="certbot python3-certbot-nginx python3-certbot-apache"
                [openssl]="openssl"
            )
            ;;
        dnf|yum)
            WEB_PACKAGES=(
                [nginx]="nginx"
                [httpd]="httpd"
                [certbot]="certbot python3-certbot-nginx python3-certbot-apache"
                [openssl]="openssl"
            )
            ;;
    esac

    # Database options (handled separately)
    declare -gA DATABASE_PACKAGES
    case $PACKAGE_MANAGER in
        apt)
            DATABASE_PACKAGES=(
                [mysql]="mysql-server"
                [postgresql]="postgresql postgresql-contrib"
            )
            ;;
        dnf|yum)
            DATABASE_PACKAGES=(
                [mysql]="mysql-server"
                [postgresql]="postgresql-server postgresql-contrib"
            )
            ;;
    esac
}

check_existing_tools() {
    print_subsection "Checking Existing Tools"

    local missing_tools=()

    # Check programming tools
    for tool in "${!PROGRAMMING_PACKAGES[@]}"; do
        case $tool in
            python3)
                if ! command -v python3 >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
            python3-pip)
                if ! command -v pip3 >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
            ansible)
                if ! command -v ansible >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
            make)
                if ! command -v make >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
            gcc)
                if ! command -v gcc >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
            git)
                if ! command -v git >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
            docker)
                if ! command -v docker >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
            golang)
                if ! command -v go >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
            rust)
                if ! command -v rustc >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
            nodejs)
                if ! command -v node >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
            cpp)
                if ! command -v g++ >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
        esac
    done

    # Check web tools
    for tool in "${!WEB_PACKAGES[@]}"; do
        case $tool in
            nginx)
                if ! command -v nginx >/dev/null 2>&1 && ! systemctl is-active --quiet nginx 2>/dev/null; then
                    missing_tools+=("$tool")
                fi
                ;;
            apache2|httpd)
                if ! command -v apache2 >/dev/null 2>&1 && ! command -v httpd >/dev/null 2>&1 && ! systemctl is-active --quiet apache2 httpd 2>/dev/null; then
                    missing_tools+=("$tool")
                fi
                ;;
            certbot)
                if ! command -v certbot >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
            openssl)
                if ! command -v openssl >/dev/null 2>&1; then
                    missing_tools+=("$tool")
                fi
                ;;
        esac
    done

    if [ ${#missing_tools[@]} -eq 0 ]; then
        echo -e "    ${GREEN}✓ All tools are already installed${RESET}"
        log "INFO" "All tools are already installed"
        return 1
    else
        echo -e "    ${YELLOW}⚠ Missing tools detected: ${missing_tools[*]}${RESET}"
        log "INFO" "Missing tools: ${missing_tools[*]}"
        return 0
    fi
}

select_groups() {
    print_section "PACKAGE GROUP SELECTION"

    echo -e "${BLUE}Available package groups:${RESET}"
    echo -e "${BOLD}1)${RESET} Programming Languages"
    echo -e "${BOLD}2)${RESET} Web Stack"
    echo -e "${BOLD}3)${RESET} Databases"
    echo -e "${BOLD}4)${RESET} All Groups"
    echo -e "${BOLD}5)${RESET} Custom Selection"
    echo

    local choice
    read -p "Select group (1-5): " choice

    case $choice in
        1)
            SELECTED_GROUPS=("programming")
            echo -e "    ${GREEN}✓ Selected: Programming Languages${RESET}"
            ;;
        2)
            SELECTED_GROUPS=("web")
            echo -e "    ${GREEN}✓ Selected: Web Stack${RESET}"
            ;;
        3)
            SELECTED_GROUPS=("database")
            echo -e "    ${GREEN}✓ Selected: Databases${RESET}"
            ;;
        4)
            SELECTED_GROUPS=("programming" "web" "database")
            echo -e "    ${GREEN}✓ Selected: All Groups${RESET}"
            ;;
        5)
            custom_selection
            ;;
        *)
            echo -e "    ${RED}✗ Invalid choice${RESET}"
            exit 1
            ;;
    esac

    log "INFO" "Selected groups: ${SELECTED_GROUPS[*]}"
}

custom_selection() {
    print_subsection "Custom Tool Selection"

    echo -e "${BLUE}Programming Languages:${RESET}"
    echo -e "  1) python3          2) python3-pip      3) ansible"
    echo -e "  4) make             5) gcc              6) git"
    echo -e "  7) docker           8) golang           9) rust"
    echo -e " 10) nodejs          11) c++/c"
    echo

    echo -e "${BLUE}Web Stack:${RESET}"
    echo -e " 12) nginx           13) apache2/httpd   14) certbot"
    echo -e " 15) openssl"
    echo

    echo -e "${BLUE}Databases:${RESET}"
    echo -e " 16) MySQL           17) PostgreSQL"
    echo

    echo -e "${YELLOW}Enter tool numbers separated by spaces (e.g., 1 3 6 12):${RESET}"
    local selections
    read -p "Tools to install: " selections

    for sel in $selections; do
        case $sel in
            1) SELECTED_GROUPS+=("python3") ;;
            2) SELECTED_GROUPS+=("python3-pip") ;;
            3) SELECTED_GROUPS+=("ansible") ;;
            4) SELECTED_GROUPS+=("make") ;;
            5) SELECTED_GROUPS+=("gcc") ;;
            6) SELECTED_GROUPS+=("git") ;;
            7) SELECTED_GROUPS+=("docker") ;;
            8) SELECTED_GROUPS+=("golang") ;;
            9) SELECTED_GROUPS+=("rust") ;;
            10) SELECTED_GROUPS+=("nodejs") ;;
            11) SELECTED_GROUPS+=("cpp") ;;
            12) SELECTED_GROUPS+=("nginx") ;;
            13) SELECTED_GROUPS+=("apache2") ;;
            14) SELECTED_GROUPS+=("certbot") ;;
            15) SELECTED_GROUPS+=("openssl") ;;
            16) SELECTED_GROUPS+=("mysql") ;;
            17) SELECTED_GROUPS+=("postgresql") ;;
            *) echo -e "    ${YELLOW}⚠ Invalid selection: $sel${RESET}" ;;
        esac
    done

    if [ ${#SELECTED_GROUPS[@]} -eq 0 ]; then
        echo -e "    ${RED}✗ No valid tools selected${RESET}"
        exit 1
    fi

    echo -e "    ${GREEN}✓ Selected tools: ${SELECTED_GROUPS[*]}${RESET}"
    log "INFO" "Custom selected tools: ${SELECTED_GROUPS[*]}"
}

install_packages() {
    local packages=("$@")

    if [ "$DRY_RUN" = true ]; then
        echo -e "    ${CYAN}[DRY-RUN]${RESET} Would install: ${packages[*]}"
        log "INFO" "[DRY-RUN] Would install: ${packages[*]}"
        return 0
    fi

    log "INFO" "Installing packages: ${packages[*]}"

    case $PACKAGE_MANAGER in
        apt)
            apt update
            apt install -y "${packages[@]}"
            ;;
        dnf|yum)
            $PACKAGE_MANAGER install -y "${packages[@]}"
            ;;
    esac

    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        INSTALLED_PACKAGES+=("${packages[@]}")
        log "INFO" "Successfully installed: ${packages[*]}"
        return 0
    else
        log "ERROR" "Failed to install: ${packages[*]} (exit code: $exit_code)"
        return 1
    fi
}

setup_docker() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "    ${CYAN}[DRY-RUN]${RESET} Would setup Docker"
        log "INFO" "[DRY-RUN] Would setup Docker"
        return 0
    fi

    log "INFO" "Setting up Docker"

    # Add user to docker group
    if id "$SUDO_USER" >/dev/null 2>&1; then
        usermod -aG docker "$SUDO_USER"
        log "INFO" "Added $SUDO_USER to docker group"
    fi

    # Start and enable Docker service
    systemctl enable docker
    systemctl start docker

    log "INFO" "Docker setup completed"
}

setup_database() {
    local db_type=$1

    if [ "$DRY_RUN" = true ]; then
        echo -e "    ${CYAN}[DRY-RUN]${RESET} Would setup $db_type database"
        log "INFO" "[DRY-RUN] Would setup $db_type database"
        return 0
    fi

    log "INFO" "Setting up $db_type database"

    case $db_type in
        mysql)
            case $PACKAGE_MANAGER in
                apt)
                    systemctl enable mysql
                    systemctl start mysql
                    ;;
                dnf|yum)
                    systemctl enable mysqld
                    systemctl start mysqld
                    ;;
            esac

            # Run secure installation
            if command -v mysql_secure_installation >/dev/null 2>&1; then
                echo -e "${YELLOW}Running MySQL secure installation...${RESET}"
                mysql_secure_installation
            fi
            ;;
        postgresql)
            case $PACKAGE_MANAGER in
                apt)
                    systemctl enable postgresql
                    systemctl start postgresql
                    ;;
                dnf|yum)
                    postgresql-setup --initdb
                    systemctl enable postgresql
                    systemctl start postgresql
                    ;;
            esac
            ;;
    esac

    log "INFO" "$db_type database setup completed"
}

select_database() {
    print_subsection "Database Selection"

    echo -e "${BLUE}Select database to install:${RESET}"
    echo -e "${BOLD}1)${RESET} MySQL"
    echo -e "${BOLD}2)${RESET} PostgreSQL"
    echo -e "${BOLD}3)${RESET} Both"
    echo -e "${BOLD}4)${RESET} Skip"
    echo

    local choice
    read -p "Select database (1-4): " choice

    case $choice in
        1)
            SELECTED_GROUPS+=("mysql")
            echo -e "    ${GREEN}✓ Selected: MySQL${RESET}"
            ;;
        2)
            SELECTED_GROUPS+=("postgresql")
            echo -e "    ${GREEN}✓ Selected: PostgreSQL${RESET}"
            ;;
        3)
            SELECTED_GROUPS+=("mysql" "postgresql")
            echo -e "    ${GREEN}✓ Selected: Both databases${RESET}"
            ;;
        4)
            echo -e "    ${CYAN}⊘ Skipping database installation${RESET}"
            return 0
            ;;
        *)
            echo -e "    ${RED}✗ Invalid choice${RESET}"
            return 1
            ;;
    esac

    log "INFO" "Selected databases: ${SELECTED_GROUPS[*]}"
}

perform_installation() {
    print_section "INSTALLATION PROCESS"

    for group in "${SELECTED_GROUPS[@]}"; do
        case $group in
            programming)
                print_subsection "Installing Programming Languages"
                for tool in "${!PROGRAMMING_PACKAGES[@]}"; do
                    echo -e "    ${BLUE}Tool: $tool${RESET}"
                    echo -e "    ${YELLOW}Packages: ${PROGRAMMING_PACKAGES[$tool]}${RESET}"
                    read -p "    Do you want to install $tool? (y/n): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        echo -e "    ${BLUE}Installing $tool...${RESET}"
                        if ! install_packages ${PROGRAMMING_PACKAGES[$tool]}; then
                            echo -e "    ${RED}✗ Failed to install $tool${RESET}"
                        else
                            echo -e "    ${GREEN}✓ Installed $tool${RESET}"
                            if [ "$tool" = "docker" ]; then
                                setup_docker
                            fi
                        fi
                    else
                        echo -e "    ${CYAN}⊘ Skipping $tool${RESET}"
                        log "INFO" "Skipped installation of $tool"
                    fi
                done
                ;;
            web)
                print_subsection "Installing Web Stack"
                for tool in "${!WEB_PACKAGES[@]}"; do
                    echo -e "    ${BLUE}Tool: $tool${RESET}"
                    echo -e "    ${YELLOW}Packages: ${WEB_PACKAGES[$tool]}${RESET}"
                    read -p "    Do you want to install $tool? (y/n): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        echo -e "    ${BLUE}Installing $tool...${RESET}"
                        if ! install_packages ${WEB_PACKAGES[$tool]}; then
                            echo -e "    ${RED}✗ Failed to install $tool${RESET}"
                        else
                            echo -e "    ${GREEN}✓ Installed $tool${RESET}"
                        fi
                    else
                        echo -e "    ${CYAN}⊘ Skipping $tool${RESET}"
                        log "INFO" "Skipped installation of $tool"
                    fi
                done
                ;;
            database)
                select_database
                for db in "${SELECTED_GROUPS[@]}"; do
                    if [[ "$db" =~ ^(mysql|postgresql)$ ]]; then
                        print_subsection "Installing $db"
                        echo -e "    ${BLUE}Tool: $db${RESET}"
                        echo -e "    ${YELLOW}Packages: ${DATABASE_PACKAGES[$db]}${RESET}"
                        read -p "    Do you want to install $db? (y/n): " -n 1 -r
                        echo
                        if [[ $REPLY =~ ^[Yy]$ ]]; then
                            echo -e "    ${BLUE}Installing $db...${RESET}"
                            if ! install_packages ${DATABASE_PACKAGES[$db]}; then
                                echo -e "    ${RED}✗ Failed to install $db${RESET}"
                            else
                                echo -e "    ${GREEN}✓ Installed $db${RESET}"
                                setup_database "$db"
                            fi
                        else
                            echo -e "    ${CYAN}⊘ Skipping $db${RESET}"
                            log "INFO" "Skipped installation of $db"
                        fi
                    fi
                done
                ;;
            *)
                # Individual tool installation
                if [[ -v PROGRAMMING_PACKAGES[$group] ]]; then
                    print_subsection "Installing $group"
                    echo -e "    ${BLUE}Tool: $group${RESET}"
                    echo -e "    ${YELLOW}Packages: ${PROGRAMMING_PACKAGES[$group]}${RESET}"
                    read -p "    Do you want to install $group? (y/n): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        echo -e "    ${BLUE}Installing $group...${RESET}"
                        if ! install_packages ${PROGRAMMING_PACKAGES[$group]}; then
                            echo -e "    ${RED}✗ Failed to install $group${RESET}"
                        else
                            echo -e "    ${GREEN}✓ Installed $group${RESET}"
                            if [ "$group" = "docker" ]; then
                                setup_docker
                            fi
                        fi
                    else
                        echo -e "    ${CYAN}⊘ Skipping $group${RESET}"
                        log "INFO" "Skipped installation of $group"
                    fi
                elif [[ -v WEB_PACKAGES[$group] ]]; then
                    print_subsection "Installing $group"
                    echo -e "    ${BLUE}Tool: $group${RESET}"
                    echo -e "    ${YELLOW}Packages: ${WEB_PACKAGES[$group]}${RESET}"
                    read -p "    Do you want to install $group? (y/n): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        echo -e "    ${BLUE}Installing $group...${RESET}"
                        if ! install_packages ${WEB_PACKAGES[$group]}; then
                            echo -e "    ${RED}✗ Failed to install $group${RESET}"
                        else
                            echo -e "    ${GREEN}✓ Installed $group${RESET}"
                        fi
                    else
                        echo -e "    ${CYAN}⊘ Skipping $group${RESET}"
                        log "INFO" "Skipped installation of $group"
                    fi
                elif [[ -v DATABASE_PACKAGES[$group] ]]; then
                    print_subsection "Installing $group"
                    echo -e "    ${BLUE}Tool: $group${RESET}"
                    echo -e "    ${YELLOW}Packages: ${DATABASE_PACKAGES[$group]}${RESET}"
                    read -p "    Do you want to install $group? (y/n): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        echo -e "    ${BLUE}Installing $group...${RESET}"
                        if ! install_packages ${DATABASE_PACKAGES[$group]}; then
                            echo -e "    ${RED}✗ Failed to install $group${RESET}"
                        else
                            echo -e "    ${GREEN}✓ Installed $group${RESET}"
                            setup_database "$group"
                        fi
                    else
                        echo -e "    ${CYAN}⊘ Skipping $group${RESET}"
                        log "INFO" "Skipped installation of $group"
                    fi
                fi
                ;;
        esac
    done
}

print_summary() {
    echo -e "\n${CYAN}${BOLD}"
    echo '╔══════════════════════════════════════════════════════════════════╗'
    echo '║                   INSTALLATION SUMMARY                          ║'
    echo '╚══════════════════════════════════════════════════════════════════╝'
    echo -e "${RESET}"

    local end_time=$(date +%s)
    local duration=$((end_time - SCRIPT_START_TIME))

    print_metric "Installation Duration" "${duration}s"
    print_metric "Distribution" "${OS_DISTRO^} $OS_VERSION"
    print_metric "Package Manager" "$PACKAGE_MANAGER"
    print_metric "Dry Run" "$([ "$DRY_RUN" = true ] && echo "Yes" || echo "No")"
    print_metric "Log File" "$LOG_FILE"

    echo -e "\n${BOLD}SELECTED GROUPS:${RESET}"
    for group in "${SELECTED_GROUPS[@]}"; do
        echo -e "  ${GREEN}✓${RESET} $group"
    done

    if [ ${#INSTALLED_PACKAGES[@]} -gt 0 ]; then
        echo -e "\n${BOLD}INSTALLED PACKAGES:${RESET}"
        for pkg in "${INSTALLED_PACKAGES[@]}"; do
            echo -e "  ${GREEN}✓${RESET} $pkg"
        done
    fi

    echo -e "\n${CYAN}${BOLD}NEXT STEPS:${RESET}"
    if [[ " ${SELECTED_GROUPS[*]} " =~ " docker " ]]; then
        echo -e "  ${BLUE}• Log out and back in for Docker group membership${RESET}"
    fi
    if [[ " ${SELECTED_GROUPS[*]} " =~ " mysql " ]] || [[ " ${SELECTED_GROUPS[*]} " =~ " postgresql " ]]; then
        echo -e "  ${BLUE}• Configure database users and permissions${RESET}"
        echo -e "  ${BLUE}• Set up database backups${RESET}"
    fi
    if [[ " ${SELECTED_GROUPS[*]} " =~ " nginx " ]] || [[ " ${SELECTED_GROUPS[*]} " =~ " apache2 " ]]; then
        echo -e "  ${BLUE}• Configure web server virtual hosts${RESET}"
        echo -e "  ${BLUE}• Set up SSL certificates with certbot${RESET}"
    fi

    echo -e "\n${DIM}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${DIM}Installation Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
    echo -e "${DIM}═══════════════════════════════════════════════════════════════${RESET}\n"
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --dry-run    Show what would be installed without actually installing"
    echo "  --help       Show this help message"
    echo
    echo "Supported distributions:"
    echo "  - Ubuntu/Debian and derivatives"
    echo "  - RHEL/Rocky/Alma/Fedora"
    echo
    echo "Available package groups:"
    echo "  - Programming Languages: python3, ansible, make, gcc, git, docker, golang, rust, nodejs, c++"
    echo "  - Web Stack: nginx, apache2/httpd, certbot, openssl"
    echo "  - Databases: MySQL, PostgreSQL"
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${RESET}"
                show_usage
                exit 1
                ;;
        esac
    done

    print_header

    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}${BOLD}DRY RUN MODE${RESET} - No actual changes will be made"
        echo
    fi

    detect_distro
    define_package_groups

    if check_existing_tools; then
        select_groups
        perform_installation
    fi

    print_summary

    if [ "$DRY_RUN" = false ]; then
        echo -e "${GREEN}${BOLD}✓ Tool installation completed successfully!${RESET}"
    else
        echo -e "${CYAN}${BOLD}✓ Dry run completed. Use without --dry-run to perform actual installation.${RESET}"
    fi
}

main "$@"
