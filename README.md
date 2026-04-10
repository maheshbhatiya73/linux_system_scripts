# Linux System Scripts

A comprehensive collection of bash scripts for Linux system administration, monitoring, security, and deployment automation.

## Overview

This repository contains modular, production-ready scripts for managing Linux systems, including Kubernetes deployment, system monitoring, backup automation, security checks, and network diagnostics.

## Directory Structure

```
├── backup/                    # Backup and data preservation scripts
├── kubernetes/               # Kubernetes installation and management
├── monitoring/               # System health monitoring
├── network/                  # Network diagnostics and testing
├── security/                 # Security scanning and hardening
└── system/                   # System setup and maintenance
```

## Modules

###  Backup (`backup/`)
- **remote_backup.sh** - Remote backup automation
- **backup.conf** - Backup configuration file

###  Kubernetes (`kubernetes/`)
- **kubernetes_installer.sh** - Master node setup and installation
- **kubernetes_worker_installer.sh** - Worker node configuration
- **kubernetes_health_checker.sh** - Cluster health monitoring
- **kubernetes.conf** - Kubernetes configuration
- **TELEGRAM_SETUP.md** - Telegram notifications setup guide

###  Monitoring (`monitoring/`)
- **system_health_checker.sh** - System resource and health monitoring

###  Network (`network/`)
- **network_speed_tester.sh** - Network connectivity and speed testing

###  Security (`security/`)
- **system_security_checker.sh** - Security vulnerability scanning and checks

###  System (`system/`)
- **first_boot_setup.sh** - Initial system configuration
- **tool_installer.sh** - Automated tool installation

## Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/maheshbhatiya73/linux_system_scripts.git
   cd linux_system_scripts
   ```

2. **Make scripts executable**
   ```bash
   chmod +x */*.sh
   ```

3. **Run a script**
   ```bash
   ./system/first_boot_setup.sh
   ```

## Usage

Each script can be run individually. Refer to the specific module documentation for detailed usage instructions:

- See [kubernetes/README.md](kubernetes/README.md) for Kubernetes setup
- See [kubernetes/TELEGRAM_SETUP.md](kubernetes/TELEGRAM_SETUP.md) for notifications

## Requirements

- Linux system (Ubuntu/Debian/CentOS)
- Bash 4.0+
- Root or sudo access (for most scripts)
- Internet connectivity (for package downloads)

## Configuration

Most scripts include configuration files (`.conf`) in their respective directories. Customize these files before running scripts:

```bash
# Edit configuration
nano backup/backup.conf
nano kubernetes/kubernetes.conf
```

## Contributing

When adding new scripts:
1. Follow the existing naming conventions
2. Include proper error handling and logging
3. Add configuration files for complex scripts
4. Document usage in module-specific README files

## License

Check individual modules for licensing information.

## Support

For issues or questions, refer to the documentation in each module's README.

---
