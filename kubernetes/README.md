# Kubernetes Auto-Installer & Health Monitoring

This directory contains automated scripts for installing, managing, and monitoring Kubernetes clusters.

## Files

- **kubernetes_installer.sh**: Main automated installation script for Kubernetes
- **kubernetes_worker_installer.sh**: Script for adding worker nodes to the cluster
- **kubernetes_health_checker.sh**: Comprehensive health monitoring with Telegram alerts
- **kubernetes.conf**: Configuration file for customizing the installation
- **HEALTH_CHECKER_README.md**: Detailed documentation for the health checker
- **TELEGRAM_SETUP.md**: Step-by-step Telegram integration guide

## Prerequisites

- Ubuntu/Debian (18.04+) or CentOS/RHEL (7+)
- Minimum 2 vCPU and 2GB RAM per node
- Root or sudo access
- Internet connectivity
- Ports 6443, 2379-2380, 10250, 10251, 10252 open on control plane

## Quick Start

### Basic Installation (Single Node)

```bash
sudo ./kubernetes_installer.sh
```

### Custom Configuration

Edit `kubernetes.conf` to customize:
- Kubernetes version
- Pod network CIDR
- Service CIDR
- Other parameters

Then run:
```bash
source kubernetes.conf
sudo ./kubernetes_installer.sh
```

### Environment Variables

You can override configuration via environment variables:

```bash
export KUBE_VERSION=1.28
export POD_CIDR=10.0.0.0/16
export CP_ENDPOINT=kubernetes.example.com:6443
sudo ./kubernetes_installer.sh
```

## Installation Steps

The script automatically performs:

1. **Prerequisites Check**: Validates OS and permissions
2. **System Setup**: 
   - Disables swap
   - Loads kernel modules
   - Configures sysctl parameters
3. **Docker Installation**: Installs container runtime
4. **Kubernetes Tools**: Installs kubectl, kubeadm, kubelet
5. **Control Plane Initialization**: Sets up master node
6. **CNI Installation**: Deploys Flannel network plugin
7. **Verification**: Validates the cluster setup

## Post-Installation

### Adding Worker Nodes

After successful control plane setup, the script saves the join command in `/tmp/kubernetes_join_command.txt`.

On worker nodes, run:
```bash
sudo <join_command_from_file>
```

### Accessing the Cluster

```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl cluster-info
```

### Deploying Applications

```bash
kubectl apply -f your-deployment.yaml
```

## Troubleshooting

### Check cluster status
```bash
kubectl get nodes
kubectl get pods -A
kubectl describe nodes
```

### View logs
```bash
journalctl -u kubelet -f
```

### Disable swap permanently
```bash
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
```

## Uninstall

To remove Kubernetes installation:

```bash
kubeadm reset -f
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
docker system prune -a --force
```

## Health Monitoring

### Kubernetes Health Checker

Monitor your Kubernetes cluster health with comprehensive diagnostics:

```bash
./kubernetes_health_checker.sh
```

**Features:**
- Cluster health summary (API server, control plane)
- Node status monitoring (Ready/NotReady)
- Pod health analysis (Running/Pending/Failed)
- Namespace overview
- Resource usage metrics
- Health score calculation (0-100)
- Automatic alerts for issues
- Telegram notifications

### Enable Telegram Alerts

See [TELEGRAM_SETUP.md](TELEGRAM_SETUP.md) for detailed instructions.

Quick setup:
```bash
# Create config file
sudo mkdir -p /etc/system_scripts
sudo tee /etc/system_scripts/auth.conf > /dev/null <<EOF
TELEGRAM_BOT_TOKEN="your_token_here"
TELEGRAM_CHAT_ID="your_chat_id_here"
EOF
sudo chmod 600 /etc/system_scripts/auth.conf
```

### Automated Monitoring (Cron)

```bash
# Add to crontab for hourly checks
crontab -e

# Every hour
0 * * * * /path/to/kubernetes_health_checker.sh > /tmp/k8s_health.log 2>&1

# Every 6 hours
0 */6 * * * /path/to/kubernetes_health_checker.sh > /tmp/k8s_health.log 2>&1
```

### Systemd Timer (Recommended)

```bash
# Use automated systemd timer setup (See HEALTH_CHECKER_README.md)
# This is more reliable than cron for system services
```


## Documentation

- [Telegram Integration Setup](TELEGRAM_SETUP.md)
