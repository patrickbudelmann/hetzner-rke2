# =============================================================================
# Private Network for RKE2 Cluster
# =============================================================================
resource "hcloud_network" "rke2" {
  name     = "${var.cluster_name}-network"
  ip_range = var.network_cidr
  labels   = local.common_labels

  # Protect the network from accidental deletion
  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Subnets
# =============================================================================

# Subnet for Control Plane Nodes
resource "hcloud_network_subnet" "control_plane" {
  network_id   = hcloud_network.rke2.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.control_plane_subnet

  depends_on = [hcloud_network.rke2]
}

# Subnet for Worker Nodes
resource "hcloud_network_subnet" "workers" {
  network_id   = hcloud_network.rke2.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.worker_subnet

  depends_on = [hcloud_network_subnet.control_plane]
}

# Subnet for Load Balancer
resource "hcloud_network_subnet" "load_balancer" {
  network_id   = hcloud_network.rke2.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.load_balancer_subnet

  depends_on = [hcloud_network_subnet.workers]
}

# =============================================================================
# Network Routes (if needed for custom routing)
# =============================================================================
# Note: Hetzner cloud networks use default routes. Add custom routes here if needed.

# =============================================================================
# Network Protection
# =============================================================================
# Note: We use lifecycle prevent_destroy on the main network resource
# to prevent accidental deletion of the entire cluster network
