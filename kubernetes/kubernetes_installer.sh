#!/bin/bash

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Configuration variables
KUBERNETES_VERSION="${KUBE_VERSION:-1.29}"
DOCKER_VERSION="${DOCKER_VERSION:-latest}"
CLUSTER_NAME="${CLUSTER_NAME:-kubernetes-cluster}"
POD_NETWORK_CIDR="${POD_CIDR:-10.244.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.96.0.0/12}"
CONTROL_PLANE_ENDPOINT="${CP_ENDPOINT:-}"

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
        log_warning "Docker is already installed"
        return
    fi

    if [[ "$OS_TYPE" == "ubuntu" ]] || [[ "$OS_TYPE" == "debian" ]]; then
        # Add Docker repository
        apt-get install -qq -y curl gnupg lsb-release
        curl -fsSL https://download.docker.com/linux/$OS_TYPE/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS_TYPE $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker
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
        # Add Kubernetes repository
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

initialize_control_plane() {
    log_info "Initializing Kubernetes control plane..."

    local init_args="--kubernetes-version=${KUBERNETES_VERSION}"
    init_args+=" --pod-network-cidr=${POD_NETWORK_CIDR}"
    init_args+=" --service-cidr=${SERVICE_CIDR}"

    if [[ -n "$CONTROL_PLANE_ENDPOINT" ]]; then
        init_args+=" --control-plane-endpoint=${CONTROL_PLANE_ENDPOINT}"
    fi

    log_info "Running kubeadm init with arguments: $init_args"
    kubeadm init $init_args

    # Set up kubeconfig for root user
    log_info "Setting up kubeconfig..."
    mkdir -p /root/.kube
    cp /etc/kubernetes/admin.conf /root/.kube/config
    chown $(id -u):$(id -g) /root/.kube/config

    # Save kubeadm join command
    log_info "Saving kubeadm join command..."
    kubeadm token create --print-join-command > /tmp/kubernetes_join_command.txt
    chmod 600 /tmp/kubernetes_join_command.txt

    log_success "Control plane initialized successfully"
    log_info "Join command saved to: /tmp/kubernetes_join_command.txt"
}

install_cni() {
    log_info "Installing Container Network Interface (Flannel)..."

    # Wait for control plane to be ready
    log_info "Waiting for control plane to be ready..."
    sleep 10

    # Apply Flannel network plugin
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

    log_success "CNI installed successfully"
}

verify_installation() {
    log_info "Verifying Kubernetes installation..."

    log_info "Kubernetes version:"
    kubectl version --client
    
    log_info "Cluster nodes:"
    kubectl get nodes -o wide
    
    log_info "Cluster info:"
    kubectl cluster-info
    
    log_info "Kubernetes components status:"
    kubectl get componentstatuses

    log_success "Verification completed"
}

display_summary() {
    cat << EOF

${GREEN}=================================================================================${NC}
${GREEN}Kubernetes Installation Summary${NC}
${GREEN}=================================================================================${NC}

Installation Details:
  - Kubernetes Version: ${KUBERNETES_VERSION}
  - Cluster Name: ${CLUSTER_NAME}
  - Pod Network CIDR: ${POD_NETWORK_CIDR}
  - Service CIDR: ${SERVICE_CIDR}
  - Control Plane Endpoint: ${CONTROL_PLANE_ENDPOINT:-Not configured}

Installed Components:
  - Docker: $(docker --version)
  - kubectl: $(kubectl version --client --short)
  - kubelet: $(kubelet --version)
  - kubeadm: $(kubeadm version -o short)

Next Steps:
  1. Copy kubeadm join command from: /tmp/kubernetes_join_command.txt
  2. Run the join command on worker nodes to add them to the cluster
  3. Verify cluster status: kubectl get nodes
  4. Deploy your applications

Useful Commands:
  - View cluster info: kubectl cluster-info
  - List all nodes: kubectl get nodes -o wide
  - View pod status: kubectl get pods --all-namespaces
  - Deploy an app: kubectl apply -f <manifest.yaml>

${GREEN}=================================================================================${NC}

EOF
}

main() {
    log_info "Starting Kubernetes auto-installer..."
    log_info "Kubernetes Version: $KUBERNETES_VERSION"

    check_prerequisites
    setup_system
    install_docker
    install_kubernetes_tools
    initialize_control_plane
    install_cni
    verify_installation
    display_summary

    log_success "Kubernetes installation completed successfully!"
}

# Run main function
main "$@"
