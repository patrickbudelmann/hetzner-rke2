# =============================================================================
# Output Values
# =============================================================================

# =============================================================================
# Cluster Information
# =============================================================================

output "cluster_name" {
  description = "Name of the RKE2 cluster"
  value       = var.cluster_name
}

output "rke2_version" {
  description = "RKE2 version installed"
  value       = var.rke2_version
}

output "rke2_cni" {
  description = "CNI plugin being used"
  value       = var.rke2_cni
}

output "rke2_token" {
  description = "RKE2 cluster token (sensitive)"
  value       = local.rke2_token
  sensitive   = true
}

output "hccm_enabled" {
  description = "Whether Hetzner Cloud Controller Manager is enabled"
  value       = var.enable_hccm
}

output "csi_driver_enabled" {
  description = "Whether Hetzner CSI driver is enabled"
  value       = var.enable_csi_driver
}

# =============================================================================
# Network Information
# =============================================================================

output "network_id" {
  description = "ID of the private network"
  value       = hcloud_network.rke2.id
}

output "network_name" {
  description = "Name of the private network"
  value       = hcloud_network.rke2.name
}

output "network_cidr" {
  description = "CIDR of the private network"
  value       = var.network_cidr
}

output "control_plane_subnet" {
  description = "Control plane subnet CIDR"
  value       = var.control_plane_subnet
}

output "worker_subnet" {
  description = "Worker subnet CIDR"
  value       = var.worker_subnet
}

# =============================================================================
# Load Balancer Information
# =============================================================================

output "load_balancer_id" {
  description = "ID of the load balancer"
  value       = hcloud_load_balancer.rke2_api.id
}

output "load_balancer_name" {
  description = "Name of the load balancer"
  value       = hcloud_load_balancer.rke2_api.name
}

output "load_balancer_public_ipv4" {
  description = "Public IPv4 address of the load balancer"
  value       = hcloud_load_balancer.rke2_api.ipv4
}

output "load_balancer_public_ipv6" {
  description = "Public IPv6 address of the load balancer"
  value       = hcloud_load_balancer.rke2_api.ipv6
}

output "load_balancer_private_ip" {
  description = "Private IP address of the load balancer"
  value       = hcloud_load_balancer_network.rke2_api.ip
}

output "kubernetes_api_endpoint" {
  description = "Kubernetes API endpoint"
  value       = var.cluster_api_dns != "" ? "https://${var.cluster_api_dns}:6443" : "https://${hcloud_load_balancer.rke2_api.ipv4}:6443"
}

output "rke2_supervisor_endpoint" {
  description = "RKE2 supervisor endpoint for node registration"
  value       = var.cluster_api_dns != "" ? "https://${var.cluster_api_dns}:9345" : "https://${hcloud_load_balancer.rke2_api.ipv4}:9345"
}

# =============================================================================
# Control Plane Information
# =============================================================================

output "control_plane_count" {
  description = "Number of control plane nodes"
  value       = var.control_plane_count
}

output "control_plane_nodes" {
  description = "Control plane node details"
  value = [
    for i, server in hcloud_server.control_plane : {
      index       = i + 1
      name        = server.name
      public_ipv4 = server.ipv4_address
      private_ip  = tolist(server.network)[0].ip
      server_type = server.server_type
      id          = server.id
    }
  ]
}

output "control_plane_ips" {
  description = "List of control plane node public IPs"
  value       = hcloud_server.control_plane[*].ipv4_address
}

output "first_control_plane_ip" {
  description = "First control plane node public IP (for SSH access)"
  value       = hcloud_server.control_plane[0].ipv4_address
}

output "first_control_plane_private_ip" {
  description = "First control plane node private IP"
  value       = tolist(hcloud_server.control_plane[0].network)[0].ip
}

# =============================================================================
# Worker Information
# =============================================================================

output "worker_count" {
  description = "Number of worker nodes"
  value       = var.worker_count
}

output "worker_nodes" {
  description = "Worker node details"
  value = [
    for i, server in hcloud_server.workers : {
      index       = i + 1
      name        = server.name
      public_ipv4 = server.ipv4_address
      private_ip  = tolist(server.network)[0].ip
      server_type = server.server_type
      id          = server.id
    }
  ]
}

output "worker_ips" {
  description = "List of worker node public IPs"
  value       = hcloud_server.workers[*].ipv4_address
}

# =============================================================================
# SSH Connection Commands
# =============================================================================

output "ssh_control_plane_commands" {
  description = "SSH commands to connect to control plane nodes"
  value = [
    for ip in hcloud_server.control_plane[*].ipv4_address :
    "ssh -i ${var.ssh_private_key_path} root@${ip}"
  ]
}

output "ssh_worker_commands" {
  description = "SSH commands to connect to worker nodes"
  value = [
    for ip in hcloud_server.workers[*].ipv4_address :
    "ssh -i ${var.ssh_private_key_path} root@${ip}"
  ]
}

# =============================================================================
# Kubeconfig Retrieval
# =============================================================================

output "get_kubeconfig_command" {
  description = "Command to retrieve kubeconfig from first control plane node"
  value       = "scp -i ${var.ssh_private_key_path} root@${hcloud_server.control_plane[0].ipv4_address}:/etc/rancher/rke2/rke2.yaml ./kubeconfig.yaml"
}

output "kubeconfig_use_cp_command" {
  description = "Command to update kubeconfig to use first control plane node (avoids TLS issues)"
  value       = "sed -i '' 's/127.0.0.1/${hcloud_server.control_plane[0].ipv4_address}/g' kubeconfig.yaml"
}

output "kubeconfig_use_dns_command" {
  description = "Command to update kubeconfig to use the cluster DNS name"
  value       = var.cluster_api_dns != "" ? "sed -i '' 's/127.0.0.1/${var.cluster_api_dns}/g' kubeconfig.yaml" : "No DNS configured. Set cluster_api_dns variable."
}

# =============================================================================
# HCCM and CSI Information
# =============================================================================

output "hccm_install_command" {
  description = "Command to install Hetzner Cloud Controller Manager (if not auto-installed)"
  value       = var.enable_hccm ? "kubectl apply -f https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/${var.hccm_version}/ccm-networks.yaml" : "HCCM auto-install disabled"
}

output "csi_install_command" {
  description = "Command to install Hetzner CSI driver (if not auto-installed)"
  value       = var.enable_csi_driver ? "kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/${var.csi_driver_version}/deploy/kubernetes/hcloud-csi.yml" : "CSI auto-install disabled"
}

# =============================================================================
# Cluster Summary
# =============================================================================

output "cluster_summary" {
  description = "Summary of the deployed cluster"
  value = <<-EOT

╔════════════════════════════════════════════════════════════════════════════╗
║                        RKE2 Cluster Deployment Complete                    ║
╚════════════════════════════════════════════════════════════════════════════╝

Cluster Information:
  Name:        ${var.cluster_name}
  Environment: ${var.environment}
  RKE2 Version: ${var.rke2_version}
  CNI Plugin:  ${var.rke2_cni}

Node Configuration:
  Control Plane: ${var.control_plane_count} nodes (${var.control_plane_server_type})
  Workers:       ${var.worker_count} nodes (${var.worker_server_type})

Network Configuration:
  Network:       ${var.network_cidr}
  Control Plane: ${var.control_plane_subnet}
  Workers:       ${var.worker_subnet}
  LB Subnet:     ${var.load_balancer_subnet}

API Endpoints:
  Kubernetes API:    ${var.cluster_api_dns != "" ? "https://${var.cluster_api_dns}:6443" : "https://${hcloud_load_balancer.rke2_api.ipv4}:6443"}
  Load Balancer IP:  ${hcloud_load_balancer.rke2_api.ipv4}

${var.cluster_api_dns != "" ? "DNS Configuration:" : "DNS Configuration:\n  No DNS configured - set cluster_api_dns for a stable endpoint"}
${var.cluster_api_dns != "" ? "  Cluster API DNS: ${var.cluster_api_dns}" : ""}
${var.cluster_api_dns != "" ? "  Create an A/AAAA record: ${var.cluster_api_dns} → ${hcloud_load_balancer.rke2_api.ipv4}" : ""}

Features Enabled:
  HCCM:          ${var.enable_hccm ? "Yes (${var.hccm_version})" : "No"}
  CSI Driver:    ${var.enable_csi_driver ? "Yes (${var.csi_driver_version})" : "No"}
  Auto Updates:  ${var.enable_auto_updates ? "Yes" : "No"}
  CIS Hardening: ${var.rke2_cis_profile != "" ? var.rke2_cis_profile : "No"}

Quick Start:
  1. Get Kubeconfig:
     scp -i ${var.ssh_private_key_path} root@${hcloud_server.control_plane[0].ipv4_address}:/etc/rancher/rke2/rke2.yaml ./kubeconfig.yaml
  
  2. Update kubeconfig server address:
     sed -i '' 's/127.0.0.1/${var.cluster_api_dns != "" ? var.cluster_api_dns : hcloud_load_balancer.rke2_api.ipv4}/g' kubeconfig.yaml
  
  3. Set KUBECONFIG:
     export KUBECONFIG=$(pwd)/kubeconfig.yaml
  
  4. Verify:
     kubectl get nodes

⚠️  IMPORTANT NOTES:
   - Wait 3-5 minutes for RKE2 installation to complete
   - If using DNS: create the DNS record pointing to the LB IP after deployment
   - The DNS name is baked into the RKE2 TLS certificate during installation

EOT
}

# =============================================================================
# Deployment Verification Commands
# =============================================================================

output "verify_cluster_command" {
  description = "Command to verify cluster is ready"
  value       = "kubectl get nodes -o wide && kubectl get pods -n kube-system"
}

output "check_hccm_command" {
  description = "Command to check HCCM status"
  value       = var.enable_hccm ? "kubectl get pods -n kube-system -l app.kubernetes.io/name=hcloud-cloud-controller-manager" : "HCCM not enabled"
}

output "check_csi_command" {
  description = "Command to check CSI driver status"
  value       = var.enable_csi_driver ? "kubectl get pods -n kube-system -l app=hcloud-csi" : "CSI driver not enabled"
}

# =============================================================================
# DNS Configuration Helper
# =============================================================================

output "dns_setup_required" {
  description = "Instructions for setting up DNS when cluster_api_dns is configured"
  value       = var.cluster_api_dns != "" ? "Create an A/AAAA record: ${var.cluster_api_dns} -> ${hcloud_load_balancer.rke2_api.ipv4}" : "No DNS configured. Set cluster_api_dns for a stable endpoint."
}
