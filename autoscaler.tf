# =============================================================================
# Hetzner Cluster Autoscaler Configuration
# =============================================================================
# Deployed via HelmChart CRD in cloud-init. Creates/deletes Hetzner Cloud
# servers based on pod scheduling pressure.
#
# Node group format: min:max:instanceType:region:name
# Autoscaler-managed nodes are created OUTSIDE Terraform (state drift).
# Use separate node pools for autoscaled vs static workers.
# =============================================================================

locals {
  autoscaler_cloud_init_raw = templatefile("${path.module}/cloud-init-worker.yaml", {
    rke2_version           = var.rke2_version
    rke2_token             = local.rke2_token
    node_name              = "autoscaled"
    cluster_name           = var.cluster_name
    server_type            = var.autoscaler_node_type
    region                 = var.region
    first_control_plane_ip = local.first_control_plane_ip
    server_url             = var.cluster_api_dns != "" ? var.cluster_api_dns : local.first_control_plane_ip
    private_ip             = ""
    enable_hccm            = var.enable_hccm
    enable_auto_updates    = var.enable_auto_updates
    taints                 = []
    labels                 = {}
  })

  autoscaler_node_group = "${var.autoscaler_min_nodes}:${var.autoscaler_max_nodes}:${var.autoscaler_node_type}:${var.region}:${var.autoscaler_node_pool_name}"

  autoscaler_cluster_config = base64encode(jsonencode({
    nodeConfigs = {
      (var.autoscaler_node_pool_name) = {
        cloudInit    = local.autoscaler_cloud_init_raw
        labels       = {}
        serverLabels = {}
        taints       = []
      }
    }
  }))
}
