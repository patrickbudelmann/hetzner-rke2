# =============================================================================
# Hetzner Cloud Configuration
# =============================================================================
variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "hcloud_token_cloudinit" {
  description = <<EOT
Dedicated Hetzner API token for cloud-init LB discovery.
This token is passed to CP nodes during first boot to discover the LB IP.
It is wiped from disk after use. You should revoke this token after deployment.
If not provided, the main hcloud_token is used (same security risk).
EOT
  type        = string
  sensitive   = true
  default     = ""
}

locals {
  hcloud_token_cloudinit = var.hcloud_token_cloudinit != "" ? var.hcloud_token_cloudinit : var.hcloud_token
}

variable "region" {
  description = "Hetzner Cloud region (nbg1, fsn1, hel1, ash, hil)"
  type        = string
  default     = "fsn1"

  validation {
    condition     = contains(["nbg1", "fsn1", "hel1", "ash", "hil"], var.region)
    error_message = "Region must be one of: nbg1, fsn1, hel1, ash, hil."
  }
}

# =============================================================================
# Cluster Configuration
# =============================================================================
variable "cluster_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "rke2"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "ssh_public_key" {
  description = "SSH public key for server access"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioner connections"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

# =============================================================================
# Control Plane Configuration
# =============================================================================
variable "control_plane_count" {
  description = "Number of control plane nodes (use odd numbers: 1, 3, 5 for etcd quorum)"
  type        = number
  default     = 3

  validation {
    condition     = var.control_plane_count >= 1 && var.control_plane_count <= 7 && var.control_plane_count % 2 == 1
    error_message = "Control plane count must be an odd number between 1 and 7 for etcd quorum (1, 3, 5, 7)."
  }
}

variable "control_plane_server_type" {
  description = "Server type for control plane nodes"
  type        = string
  default     = "cpx21"
}

variable "control_plane_image" {
  description = "OS image for control plane nodes"
  type        = string
  default     = "ubuntu-24.04"
}

variable "control_plane_volumes" {
  description = "Additional volumes for control plane nodes (size in GB, 0 to disable)"
  type        = number
  default     = 0
}

# =============================================================================
# Worker Node Configuration
# =============================================================================
variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 0
    error_message = "Worker count must be 0 or greater."
  }
}

variable "worker_server_type" {
  description = "Server type for worker nodes"
  type        = string
  default     = "cpx31"
}

variable "worker_image" {
  description = "OS image for worker nodes"
  type        = string
  default     = "ubuntu-24.04"
}

variable "worker_volumes" {
  description = "Additional volumes for worker nodes (size in GB, 0 to disable)"
  type        = number
  default     = 0
}

# =============================================================================
# Network Configuration
# =============================================================================
variable "network_zone" {
  description = "Network zone (eu-central, us-east, us-west, ap-southeast)"
  type        = string
  default     = "eu-central"

  validation {
    condition     = contains(["eu-central", "us-east", "us-west", "ap-southeast"], var.network_zone)
    error_message = "Network zone must be one of: eu-central, us-east, us-west, ap-southeast."
  }
}

variable "network_cidr" {
  description = "CIDR block for the private network"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "Network CIDR must be a valid IPv4 CIDR block."
  }
}

variable "control_plane_subnet" {
  description = "Subnet for control plane nodes"
  type        = string
  default     = "10.0.1.0/24"
}

variable "worker_subnet" {
  description = "Subnet for worker nodes"
  type        = string
  default     = "10.0.2.0/24"
}

variable "load_balancer_subnet" {
  description = "Subnet for load balancer"
  type        = string
  default     = "10.0.3.0/24"
}

# =============================================================================
# Firewall Configuration
# =============================================================================
variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed to access SSH (restrict to your IP for security)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "additional_allowed_cidrs" {
  description = "Additional CIDR blocks allowed for external access (e.g., VPN, office)"
  type        = list(string)
  default     = []
}

variable "enable_nodeport_access" {
  description = "Enable NodePort service access from external CIDRs"
  type        = bool
  default     = false
}

# =============================================================================
# RKE2 Configuration
# =============================================================================
variable "rke2_version" {
  description = "RKE2 version to install (e.g., v1.29.3+rke2r1)"
  type        = string
  default     = "v1.29.3+rke2r1"
}

variable "rke2_token" {
  description = "Token for RKE2 cluster registration (auto-generated if empty)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "rke2_cni" {
  description = "CNI plugin to use (cilium, canal, calico, flannel, none)"
  type        = string
  default     = "cilium"

  validation {
    condition     = contains(["cilium", "canal", "calico", "flannel", "none"], var.rke2_cni)
    error_message = "CNI must be one of: cilium, canal, calico, flannel, none."
  }
}

variable "rke2_cis_profile" {
  description = "Enable CIS hardening profile (cis or cis-1.23)"
  type        = string
  default     = ""  # Empty means no CIS hardening
}

variable "rke2_disable_etcd_snapshots" {
  description = "Disable automated etcd snapshots"
  type        = bool
  default     = false
}

variable "rke2_etcd_snapshot_interval" {
  description = "etcd snapshot interval in hours"
  type        = number
  default     = 6
}

variable "rke2_etcd_snapshot_retention" {
  description = "Number of etcd snapshots to retain"
  type        = number
  default     = 24
}

# =============================================================================
# Hetzner Cloud Controller Manager (HCCM)
# =============================================================================
variable "enable_hccm" {
  description = "Enable Hetzner Cloud Controller Manager"
  type        = bool
  default     = true
}

variable "hccm_version" {
  description = "HCCM version to install"
  type        = string
  default     = "v1.20.0"
}

# =============================================================================
# Hetzner CSI Driver
# =============================================================================
variable "enable_csi_driver" {
  description = "Enable Hetzner CSI driver for persistent volumes"
  type        = bool
  default     = true
}

variable "csi_driver_version" {
  description = "CSI driver version to install"
  type        = string
  default     = "v2.7.0"
}

# =============================================================================
# Load Balancer Configuration
# =============================================================================
variable "lb_type" {
  description = "Load balancer type (lb11, lb21, lb31)"
  type        = string
  default     = "lb11"

  validation {
    condition     = contains(["lb11", "lb21", "lb31"], var.lb_type)
    error_message = "Load balancer type must be one of: lb11, lb21, lb31."
  }
}

variable "lb_algorithm" {
  description = "Load balancing algorithm (round_robin, least_connections)"
  type        = string
  default     = "round_robin"

  validation {
    condition     = contains(["round_robin", "least_connections"], var.lb_algorithm)
    error_message = "LB algorithm must be round_robin or least_connections."
  }
}

variable "lb_health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10
}

variable "lb_health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "lb_health_check_retries" {
  description = "Number of health check retries before marking unhealthy"
  type        = number
  default     = 3
}

variable "lb_health_check_port" {
  description = "Port for health checks (uses API server port 6443)"
  type        = number
  default     = 6443
}

# =============================================================================
# Node Labels and Taints
# =============================================================================
variable "control_plane_labels" {
  description = "Additional labels for control plane nodes"
  type        = map(string)
  default     = {}
}

variable "worker_labels" {
  description = "Additional labels for worker nodes"
  type        = map(string)
  default     = {}
}

variable "control_plane_taints" {
  description = "Taints for control plane nodes"
  type        = list(string)
  default     = ["node-role.kubernetes.io/control-plane:NoSchedule"]
}

variable "worker_taints" {
  description = "Taints for worker nodes"
  type        = list(string)
  default     = []
}

# =============================================================================
# Backup and Maintenance
# =============================================================================
variable "enable_backups" {
  description = "Enable automated backups for control plane nodes"
  type        = bool
  default     = true
}

variable "backup_window" {
  description = "Backup window time (HH:MM format)"
  type        = string
  default     = "04:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):([0-5][0-9])$", var.backup_window))
    error_message = "Backup window must be in HH:MM format (24-hour)."
  }
}

variable "enable_auto_updates" {
  description = "Enable automatic security updates (via unattended-upgrades)"
  type        = bool
  default     = true
}

# =============================================================================
# Local Values
# =============================================================================
locals {
  # Generate a random token if not provided
  rke2_token = var.rke2_token != "" ? var.rke2_token : random_password.rke2_token[0].result

  # Determine first control plane IP
  first_control_plane_ip = cidrhost(var.control_plane_subnet, 10)

  # Common labels for all resources
  common_labels = {
    cluster     = var.cluster_name
    environment = var.environment
    managed_by  = "terraform"
  }

  # Control plane labels merged with common labels
  control_plane_labels = merge(
    local.common_labels,
    { node-type = "control-plane" },
    var.control_plane_labels
  )

  # Worker labels merged with common labels
  worker_labels = merge(
    local.common_labels,
    { node-type = "worker" },
    var.worker_labels
  )

  # Check if we need wireguard ports (for Cilium with encryption)
  needs_wireguard = var.rke2_cni == "cilium"

  # RKE2 config directory
  rke2_config_dir = "/etc/rancher/rke2"
}

# Generate random token if not provided
resource "random_password" "rke2_token" {
  count   = var.rke2_token == "" ? 1 : 0
  length  = 48
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# Generate random HCCM secret if needed
resource "random_password" "hccm_encryption_passphrase" {
  count   = var.enable_csi_driver ? 1 : 0
  length  = 32
  special = true
}
