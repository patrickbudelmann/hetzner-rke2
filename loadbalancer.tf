# =============================================================================
# Hetzner Load Balancer for RKE2 API
# =============================================================================

resource "hcloud_load_balancer" "rke2_api" {
  name               = "${var.cluster_name}-api-lb"
  load_balancer_type = var.lb_type
  location           = var.region
  labels             = local.common_labels

  # Load balancing algorithm
  algorithm {
    type = var.lb_algorithm
  }

  lifecycle {
    prevent_destroy = false  # Can be recreated without data loss
  }
}

# =============================================================================
# Attach Load Balancer to Private Network
# =============================================================================

resource "hcloud_load_balancer_network" "rke2_api" {
  load_balancer_id = hcloud_load_balancer.rke2_api.id
  network_id       = hcloud_network.rke2.id
  ip               = cidrhost(var.load_balancer_subnet, 10)

  depends_on = [
    hcloud_load_balancer.rke2_api,
    hcloud_network_subnet.load_balancer,
  ]
}

# =============================================================================
# Load Balancer Targets (Control Plane Nodes)
# =============================================================================

resource "hcloud_load_balancer_target" "control_plane" {
  count = var.control_plane_count

  type             = "server"
  load_balancer_id = hcloud_load_balancer.rke2_api.id
  server_id        = hcloud_server.control_plane[count.index].id
  use_private_ip   = true

  depends_on = [
    hcloud_load_balancer_network.rke2_api,
    hcloud_server.control_plane,
  ]

  # Ensure the server is fully created before adding as target
  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Load Balancer Services
# =============================================================================

# Kubernetes API Server Service (Port 6443)
resource "hcloud_load_balancer_service" "kube_api" {
  load_balancer_id = hcloud_load_balancer.rke2_api.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443

  # Health check configuration
  health_check {
    protocol = "tcp"
    port     = var.lb_health_check_port
    interval = var.lb_health_check_interval
    timeout  = var.lb_health_check_timeout
    retries  = var.lb_health_check_retries
  }

  # Enable proxy protocol if needed (disabled for API server)
  proxyprotocol = false

  depends_on = [
    hcloud_load_balancer_target.control_plane,
  ]
}

# RKE2 Supervisor Service (Port 9345) - for node registration
resource "hcloud_load_balancer_service" "rke2_supervisor" {
  load_balancer_id = hcloud_load_balancer.rke2_api.id
  protocol         = "tcp"
  listen_port      = 9345
  destination_port = 9345

  # Health check for supervisor
  health_check {
    protocol = "tcp"
    port     = 9345
    interval = var.lb_health_check_interval
    timeout  = var.lb_health_check_timeout
    retries  = var.lb_health_check_retries
  }

  proxyprotocol = false

  depends_on = [
    hcloud_load_balancer_target.control_plane,
  ]
}

# =============================================================================
# Optional: Additional Load Balancer Services
# =============================================================================

# Example: If you want direct access to node ports through LB
# resource "hcloud_load_balancer_service" "http" {
#   count            = var.enable_http_lb ? 1 : 0
#   load_balancer_id = hcloud_load_balancer.rke2_api.id
#   protocol         = "tcp"
#   listen_port      = 80
#   destination_port = 80
#
#   health_check {
#     protocol = "tcp"
#     port     = 80
#     interval = 15
#     timeout  = 10
#     retries  = 3
#   }
# }

# =============================================================================
# Load Balancer Protection
# =============================================================================
# Note: We don't use prevent_destroy on the LB as it can be easily recreated
# The API endpoint IP will change, so make sure to update your kubeconfig
