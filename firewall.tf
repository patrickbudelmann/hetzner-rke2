# =============================================================================
# Hetzner Cloud Firewall - Minimal WAN Access
# Based on RKE2 and CNI port requirements
# =============================================================================

# Firewall for Control Plane Nodes
resource "hcloud_firewall" "control_plane" {
  name = "${var.cluster_name}-control-plane-firewall"

  # SSH access - restricted to allowed CIDRs (should be your IP only)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = var.allowed_ssh_cidr
    description = "SSH access"
  }

  # ICMP for basic connectivity
  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "ICMP (ping)"
  }

  # Kubernetes API Server - exposed to internet via LB, but nodes need direct access too
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "6443"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Kubernetes API Server"
  }

  # RKE2 supervisor - for node registration and communication
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "9345"
    source_ips  = concat([var.network_cidr], var.additional_allowed_cidrs)
    description = "RKE2 supervisor (node registration)"
  }

  # etcd peer-to-peer - internal only
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "2379-2380"
    source_ips  = [var.network_cidr]
    description = "etcd peer-to-peer communication"
  }

  # Kubelet - for metrics and exec/logs
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "10250"
    source_ips  = [var.network_cidr]
    description = "Kubelet API"
  }

  # Kubernetes scheduler
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "10259"
    source_ips  = [var.network_cidr]
    description = "kube-scheduler"
  }

  # Kubernetes controller manager
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "10257"
    source_ips  = [var.network_cidr]
    description = "kube-controller-manager"
  }

  # CNI VXLAN (Canal/Flannel) - internal only
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "8472"
    source_ips  = [var.network_cidr]
    description = "CNI VXLAN (Canal/Flannel)"
  }

  # CNI WireGuard (Cilium with encryption) - internal only
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "51820-51821"
    source_ips  = [var.network_cidr]
    description = "CNI WireGuard (Cilium encryption)"
  }

  # Allow all other traffic within the private network
  # This ensures node-to-node communication works for services, pods, etc.
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "1-65535"
    source_ips  = [var.network_cidr]
    description = "All TCP within private network"
  }

  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "1-65535"
    source_ips  = [var.network_cidr]
    description = "All UDP within private network"
  }

  labels = local.common_labels
}

# Firewall for Worker Nodes
resource "hcloud_firewall" "workers" {
  name = "${var.cluster_name}-worker-firewall"

  # SSH access
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = var.allowed_ssh_cidr
    description = "SSH access"
  }

  # ICMP for basic connectivity
  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "ICMP (ping)"
  }

  # NodePort Services (optional - for direct NodePort access)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "30000-32767"
    source_ips  = concat([var.network_cidr], var.additional_allowed_cidrs)
    description = "Kubernetes NodePort Services"
  }

  # CNI VXLAN (Canal/Flannel)
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "8472"
    source_ips  = [var.network_cidr]
    description = "CNI VXLAN (Canal/Flannel)"
  }

  # CNI WireGuard (Cilium with encryption)
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "51820-51821"
    source_ips  = [var.network_cidr]
    description = "CNI WireGuard (Cilium encryption)"
  }

  # Allow all traffic within the private network
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "1-65535"
    source_ips  = [var.network_cidr]
    description = "All TCP within private network"
  }

  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "1-65535"
    source_ips  = [var.network_cidr]
    description = "All UDP within private network"
  }

  labels = local.common_labels
}

# =============================================================================
# Firewall Attachment to Servers
# Note: Firewalls are attached in servers.tf via firewall_ids
# =============================================================================
