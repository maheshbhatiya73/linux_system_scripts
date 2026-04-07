# System Administration Scripts

A comprehensive collection of automated bash scripts for Linux server administration, setup, health monitoring, and security auditing. These scripts support both Debian/Ubuntu and RHEL/Fedora-based distributions.

---

## Scripts Overview

### 1. **first_boot_setup.sh** - Initial Server Configuration
**Purpose:** Automated first-boot server initialization and configuration

**Key Features:**
- Operating system detection (Ubuntu/Debian, RHEL/Fedora families)
- System hostname and timezone configuration
- System locale and language setup
- Network interface configuration
- Firewall initialization and UFW/firewalld setup
- SSH server hardening and configuration
- User account creation and sudo privileges
- Package manager updates
- Essential system packages installation
- Repository management
- Basic security hardening
- System initialization logging

**Usage:**
```bash
sudo bash first_boot_setup.sh
```

**Requirements:**
- Root or sudo privileges
- Supported Linux distributions:
  - Ubuntu/Debian/Linux Mint/PopOS
  - RHEL/CentOS/Fedora/Rocky/AlmaLinux

**Output:**
- Formatted setup wizard with prompts
- Summary report of all configurations applied
- Log files for reference

---

### 2. **tool_installer.sh** - Package Group Installation
**Purpose:** Flexible and interactive package installation for development and production environments

**Key Features:**
- Multi-group package installation (Programming, Web Stack, Databases)
- Distribution-aware package mapping
- Pre-installation tool detection
- Dry-run mode for testing
- Individual tool selection or group selection
- Docker service setup and group configuration
- Database initialization (MySQL/PostgreSQL)
- Automated package manager detection
- Installation verification
- Comprehensive logging

**Available Package Groups:**

| Group | Packages |
|-------|----------|
| **Programming Languages** | Python3, pip, Ansible, Make, GCC, Git, Docker, Go, Rust, Node.js, C++ |
| **Web Stack** | Nginx, Apache2/httpd, Certbot, OpenSSL |
| **Databases** | MySQL, PostgreSQL |

**Usage:**
```bash
# Interactive mode - select packages manually
sudo bash tool_installer.sh

# Dry-run mode - preview what would be installed
sudo bash tool_installer.sh --dry-run

# Help
bash tool_installer.sh --help
```

**Selection Methods:**
1. **Group Selection (1-4):** Install pre-defined groups
   - Programming Languages
   - Web Stack
   - Databases
   - All Groups
2. **Custom Selection (5):** Pick individual tools by number

**Key Options:**
- `--dry-run`: Preview installation without making changes
- `--help`: Display usage information

**Requirements:**
- Root or sudo privileges
- Compatible package manager (apt, dnf, or yum)

**Post-Installation Steps:**
- Docker: Log out and back in for group membership
- Databases: Configure users and permissions, set up backups
- Web Servers: Configure virtual hosts, set up SSL certificates

---

### 3. **system_health_checker.sh** - Infrastructure Health Monitoring
**Purpose:** Comprehensive system health diagnostic and performance monitoring

**Key Features:**
- **System Core Analysis:**
  - Uptime and system load monitoring
  - Kernel version and OS information
  - Swap memory analysis

- **Compute Metrics:**
  - CPU usage and utilization
  - Process count and zombie process detection
  - Context switching analysis

- **Memory Management:**
  - RAM usage and allocation
  - Memory pressure indicators
  - Available vs. used memory

- **Storage Analysis:**
  - Disk space usage by mount point
  - Partition utilization percentages
  - Inode usage tracking

- **Network Diagnostics:**
  - Interface status and statistics
  - Network connectivity tests
  - Packet loss and latency checks

- **Service Monitoring:**
  - Critical service status (SSH, DNS, time sync)
  - Service health verification
  - Dependency checks

- **Security Checks:**
  - Firewall status
  - SELinux/AppArmor compliance
  - Failed login attempts

- **System Updates:**
  - Available updates check
  - Security patches status
  - Package manager status

- **Advanced Features:**
  - Overall health score (weighted calculation)
  - Progress tracking with visual indicators
  - Thresholds with warning/critical levels
  - Telegram notifications support
  - Verbose output mode
  - Detailed health reports

**Health Score Thresholds:**
- CPU: Warning 70%, Critical 90%
- Memory: Warning 80%, Critical 95%
- Disk: Warning 80%, Critical 95%
- System Load: Warning 20x, Critical 50x

**Usage:**
```bash
# Standard health check
bash system_health_checker.sh

# With verbose output
bash system_health_checker.sh -v
```

**Telegram Integration:**
Configure `/etc/system_scripts/auth.conf` with:
```bash
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
```

**Output:**
- Color-coded health status
- Per-category scores with weight distribution
- Overall system health percentage
- Detailed recommendations
- Summary report

---

### 4. **system_security_checker.sh** - Security Audit and Hardening Assessment
**Purpose:** Comprehensive system security audit and compliance verification

**Key Features:**
- **SSH Hardening Verification:**
  - SSH daemon configuration review
  - Key-based authentication check
  - Password authentication status
  - Root login policy
  - Port configuration

- **Privilege Escalation Analysis:**
  - sudo configuration audit
  - sudoers file permissions
  - Privilege escalation vectors detection
  - sudo logging verification

- **Brute-Force Protection:**
  - fail2ban status
  - SSH rate limiting
  - Connection throttling
  - Ban list review

- **Mandatory Access Control (MAC):**
  - SELinux enforcement status (RHEL systems)
  - AppArmor mode (Debian systems)
  - MAC policy coverage
  - Policy violations

- **Audit Coverage:**
  - auditd daemon status
  - Audit rules verification
  - Logging configuration
  - Audit log retention

- **File Integrity Monitoring:**
  - AIDE or AIDE-like tools status
  - Critical file monitoring
  - Baseline database integrity
  - Change detection

- **Firewall Policy:**
  - Firewall service status (UFW/firewalld)
  - Inbound/outbound rules
  - Default policies
  - Port exposure analysis

- **Kernel Hardening:**
  - Kernel parameters verification
  - ASLR enforcement
  - DEP/NX enablement
  - Core dump restrictions

- **Service Sandboxing:**
  - Service isolation verification
  - Container security
  - Process confinement
  - Resource limits

- **Temporary Directory Security:**
  - /tmp permissions
  - /var/tmp permissions
  - noexec mount options
  - World-writable directory audits

- **Advanced Features:**
  - Overall security score (weighted calculation)
  - Risk assessment by category
  - Compliance recommendations
  - Telegram alert support
  - Detailed audit trail
  - Vulnerability prioritization

**Security Score Weights:**
- SSH Hardening: 15%
- Privilege Escalation: 15%
- Brute-Force Protection: 15%
- Mandatory Access Control: 10%
- Audit Coverage: 10%
- File Integrity: 10%
- Firewall Policy: 10%
- Kernel Hardening: 5%
- Service Sandboxing: 5%
- Temp Directories: 5%

**Usage:**
```bash
# Run security audit
sudo bash system_security_checker.sh

# Verbose security audit
sudo bash system_security_checker.sh -v
```

**Telegram Integration:**
Configure `/etc/system_scripts/auth.conf` with:
```bash
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
```

**Output:**
- Detailed security findings
- Risk level indicators (✓ Pass, ⚠ Warning, ✗ Critical)
- Per-category security scores
- Overall security percentage
- Remediation recommendations
- Compliance report

---

## Common Usage Patterns

### Complete New Server Setup
```bash
# 1. Initial configuration
sudo bash first_boot_setup.sh

# 2. Install required tools
sudo bash tool_installer.sh

# 3. Verify system health
bash system_health_checker.sh

# 4. Run security audit
sudo bash system_security_checker.sh
```

### Regular Monitoring Schedule
```bash
# Add to crontab for daily checks
0 6 * * * /opt/projects/scripts/system_health_checker.sh >> /var/log/health_check.log 2>&1
0 8 * * * /opt/projects/scripts/system_security_checker.sh >> /var/log/security_check.log 2>&1
```

### Pre-Deployment Verification
```bash
# Run all checks before production deployment
for script in first_boot_setup.sh system_health_checker.sh system_security_checker.sh; do
    echo "Running $script..."
    sudo bash "$script" --dry-run || bash "$script"
done
```

---

## Features Common to All Scripts

### Visual Formatting
- Color-coded output (Green: Pass, Yellow: Warning, Red: Critical, Blue: Info, Cyan: Skip)
- ASCII art headers and dividers
- Progress bars and status indicators
- Formatted metric displays

### System Detection
- Automatic distribution detection
- Package manager identification
- Service manager compatibility
- Logging to `/var/log/` with timestamps

### Error Handling
- Comprehensive error checking
- Detailed error messages
- Graceful failure handling
- Exit codes

### Logging
- Detailed operation logs
- Timestamped entries
- Error and info separation
- Log file locations displayed in output

### Permissions
- Privilege verification
- Sudo elevation checks
- Permission error handling

---

## 🛡️ Security Considerations

1. **Always Review:**
   - Run scripts in dry-run mode first when available
   - Review proposed changes before execution
   - Test on non-production systems first

2. **Permissions:**
   - Most scripts require root/sudo privileges
   - Review log files after execution
   - Maintain audit trails

3. **Configuration:**
   - Back up system configs before running
   - Keep distribution-specific requirements in mind
   - Monitor changes with health/security checkers

4. **Updates:**
   - Run health checker before package updates
   - Verify system state after installation
   - Review security audit after changes

---

## Supported Distributions

### Debian Family
- Ubuntu (18.04+)
- Debian (10+)
- Linux Mint
- PopOS

### RHEL Family
- RHEL (7+)
- CentOS (7+)
- Fedora
- Rocky Linux
- AlmaLinux
- Amazon Linux

---

## Log Files

Scripts create logs in the following locations:

- `tool_installer.sh`: `/var/log/tool_installer_YYYYMMDD_HHMMSS.log`
- `system_health_checker.sh`: `/var/log/system_health_check_YYYYMMDD_HHMMSS.log`
- `system_security_checker.sh`: `/var/log/system_security_check_YYYYMMDD_HHMMSS.log`
- `first_boot_setup.sh`: `/var/log/first_boot_setup_YYYYMMDD_HHMMSS.log`

---

## Quick Start

```bash
cd /opt/scripts

# Make all scripts executable
chmod +x *.sh

# Start with first boot setup
sudo ./first_boot_setup.sh

# Install development tools
sudo ./tool_installer.sh

# Monitor system health
./system_health_checker.sh

# Audit security posture
sudo ./system_security_checker.sh
```

---

## Support & Configuration

### Telegram Notifications

Create `/etc/system_scripts/auth.conf`:
```bash
TELEGRAM_BOT_TOKEN="your_telegram_bot_token_here"
TELEGRAM_CHAT_ID="your_telegram_chat_id_here"
```

Both health and security checkers will send alerts via Telegram when configured.

---

## ⚠️ Disclaimer

- These scripts modify system configuration
- Always test in safe environments first
- Maintain backups before running
- Review all changes before production deployment
- Not responsible for unintended system changes

---

## License & Attribution

These scripts are provided as system administration utilities for Linux systems.

---

## Next Steps

1. Review this README completely
2. Test scripts in a safe environment
3. Customize configurations as needed
4. Schedule regular monitoring runs
5. Integrate Telegram notifications for critical alerts
6. Set up log aggregation and review process
