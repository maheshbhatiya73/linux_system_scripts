#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

KUBERNETES_VERSION="${KUBE_VERSION:-1.29}"
DOCKER_VERSION="${DOCKER_VERSION:-latest}"
JOIN_COMMAND="${JOIN_COMMAND:-}"

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Check OS type
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_TYPE=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "Unable to determine OS type"
        exit 1
    fi

    log_success "Prerequisites check completed (OS: $OS_TYPE $OS_VERSION)"
}

setup_system() {
    log_info "Setting up system prerequisites..."

    # Disable swap
    log_info "Disabling swap..."
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab

    # Load kernel modules
    log_info "Loading kernel modules..."
    cat > /etc/modules-load.d/kubernetes.conf <<EOF
overlay
br_netfilter
EOF

    modprobe overlay
    modprobe br_netfilter

    # Set kernel parameters
    log_info "Configuring kernel parameters..."
    cat > /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
vm.overcommit_memory = 1
kernel.panic = 10
kernel.panic_on_oops = 1
EOF

    sysctl --system > /dev/null

    # Update package manager
    log_info "Updating package manager..."
    if [[ "$OS_TYPE" == "ubuntu" ]] || [[ "$OS_TYPE" == "debian" ]]; then
        apt-get update -qq
    elif [[ "$OS_TYPE" == "centos" ]] || [[ "$OS_TYPE" == "rhel" ]]; then
        yum update -y -q
    fi

    log_success "System setup completed"
}

install_docker() {
    log_info "Installing Docker..."

    if command -v docker &> /dev/null; then
        log_info "Docker is already installed"
        return
    fi

    if [[ "$OS_TYPE" == "ubuntu" ]] || [[ "$OS_TYPE" == "debian" ]]; then
        apt-get install -qq -y curl gnupg lsb-release
        curl -fsSL https://download.docker.com/linux/$OS_TYPE/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS_TYPE $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update -qq
        apt-get install -qq -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    elif [[ "$OS_TYPE" == "centos" ]] || [[ "$OS_TYPE" == "rhel" ]]; then
        yum install -y -q yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi

    # Configure containerd
    log_info "Configuring containerd..."
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml > /dev/null
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    # Enable and start Docker
    systemctl daemon-reload
    systemctl enable docker containerd
    systemctl start docker containerd

    log_success "Docker installed successfully"
}

install_kubernetes_tools() {
    log_info "Installing Kubernetes tools (kubectl, kubeadm, kubelet)..."

    if [[ "$OS_TYPE" == "ubuntu" ]] || [[ "$OS_TYPE" == "debian" ]]; then
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

        apt-get update -qq
        apt-get install -qq -y kubelet kubeadm kubectl

    elif [[ "$OS_TYPE" == "centos" ]] || [[ "$OS_TYPE" == "rhel" ]]; then
        cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/rpm/repodata/repomd.xml.key
EOF

        yum install -y -q kubelet kubeadm kubectl
    fi

    # Enable kubelet service
    systemctl enable kubelet

    log_success "Kubernetes tools installed successfully"
}


join_cluster() {
    log_info "Joining Kubernetes cluster..."

    if [[ -z "$JOIN_COMMAND" ]]; then
        log_error "JOIN_COMMAND is not set. Please provide the kubeadm join command."
        log_error "Example: export JOIN_COMMAND='kubeadm join 192.168.1.100:6443 --token ...'"
        exit 1
    fi

    log_info "Running: $JOIN_COMMAND"
    eval "$JOIN_COMMAND"

    log_success "Worker node joined cluster successfully"
}

main() {
    log_info "Starting Kubernetes worker node installer..."
    log_info "Kubernetes Version: $KUBERNETES_VERSION"

    check_prerequisites
    setup_system
    install_docker
    install_kubernetes_tools
    join_cluster

    log_success "Kubernetes worker node installation completed successfully!"
    log_info "Node status will be available shortly on the control plane:"
    log_info "kubectl get nodes"
}

# Run main function
main "$@"
