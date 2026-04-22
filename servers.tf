# =============================================================================
# SSH Key
# =============================================================================
resource "hcloud_ssh_key" "rke2" {
  name       = "${var.cluster_name}-ssh-key"
  public_key = var.ssh_public_key
  labels     = local.common_labels
}

# =============================================================================
# Control Plane Nodes
# =============================================================================
resource "hcloud_server" "control_plane" {
  count = var.control_plane_count

  name        = "${var.cluster_name}-cp-${count.index + 1}"
  server_type = var.control_plane_server_type
  image       = var.control_plane_image
  location    = var.region

  ssh_keys = [hcloud_ssh_key.rke2.id]

  network {
    network_id = hcloud_network.rke2.id
    ip         = cidrhost(var.control_plane_subnet, count.index + 10)
  }

  firewall_ids = [hcloud_firewall.control_plane.id]
  labels       = local.control_plane_labels

  depends_on = [
    hcloud_network_subnet.control_plane,
  ]

  backups = var.enable_backups

  user_data = templatefile("${path.module}/cloud-init-control-plane.yaml", {
    rke2_version              = var.rke2_version
    rke2_token                = local.rke2_token
    node_name                 = "${var.cluster_name}-cp-${count.index + 1}"
    cluster_name              = var.cluster_name
    server_type               = var.control_plane_server_type
    region                    = var.region
    is_first_server           = count.index == 0
    first_control_plane_ip    = local.first_control_plane_ip
    private_ip                = cidrhost(var.control_plane_subnet, count.index + 10)
    cluster_api_dns           = var.cluster_api_dns
    cni                       = var.rke2_cni
    cis_profile               = var.rke2_cis_profile
    disable_etcd_snapshots    = var.rke2_disable_etcd_snapshots
    etcd_snapshot_interval    = var.rke2_etcd_snapshot_interval
    etcd_snapshot_retention   = var.rke2_etcd_snapshot_retention
    enable_hccm               = var.enable_hccm
    hccm_version              = var.hccm_version
    enable_csi                = var.enable_csi_driver
    csi_version               = var.csi_driver_version
    csi_encryption_passphrase = var.enable_csi_driver && length(random_password.hccm_encryption_passphrase) > 0 ? random_password.hccm_encryption_passphrase[0].result : ""
    hcloud_token              = var.hcloud_token
    network_id                = hcloud_network.rke2.id
    network_name              = hcloud_network.rke2.name
    enable_auto_updates       = var.enable_auto_updates
    taints                    = var.control_plane_taints
    labels                    = var.control_plane_labels
  })

  lifecycle {
    ignore_changes = [
      user_data,
      ssh_keys,
      image,
    ]
    prevent_destroy = false
  }
}

# =============================================================================
# Control Plane Volumes (Optional)
# =============================================================================
resource "hcloud_volume" "control_plane" {
  count = var.control_plane_volumes > 0 ? var.control_plane_count : 0

  name      = "${var.cluster_name}-cp-${count.index + 1}-data"
  size      = var.control_plane_volumes
  server_id = hcloud_server.control_plane[count.index].id
  format    = "ext4"
  location  = var.region

  labels = merge(local.control_plane_labels, {
    purpose = "persistent-data"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Worker Nodes
# =============================================================================
resource "hcloud_server" "workers" {
  count = var.worker_count

  name        = "${var.cluster_name}-worker-${count.index + 1}"
  server_type = var.worker_server_type
  image       = var.worker_image
  location    = var.region

  ssh_keys = [hcloud_ssh_key.rke2.id]

  network {
    network_id = hcloud_network.rke2.id
    ip         = cidrhost(var.worker_subnet, count.index + 10)
  }

  firewall_ids = [hcloud_firewall.workers.id]
  labels       = local.worker_labels

  depends_on = [
    hcloud_server.control_plane,
    hcloud_network_subnet.workers,
  ]

  user_data = templatefile("${path.module}/cloud-init-worker.yaml", {
    rke2_version           = var.rke2_version
    rke2_token             = local.rke2_token
    node_name              = "${var.cluster_name}-worker-${count.index + 1}"
    cluster_name           = var.cluster_name
    server_type            = var.worker_server_type
    region                 = var.region
    first_control_plane_ip = local.first_control_plane_ip
    server_url             = var.cluster_api_dns != "" ? var.cluster_api_dns : local.first_control_plane_ip
    private_ip             = cidrhost(var.worker_subnet, count.index + 10)
    enable_hccm            = var.enable_hccm
    enable_auto_updates    = var.enable_auto_updates
    taints                 = var.worker_taints
    labels                 = var.worker_labels
  })

  lifecycle {
    ignore_changes = [
      user_data,
      ssh_keys,
      image,
    ]
    prevent_destroy = false
  }
}

# =============================================================================
# Worker Volumes (Optional)
# =============================================================================
resource "hcloud_volume" "workers" {
  count = var.worker_volumes > 0 ? var.worker_count : 0

  name      = "${var.cluster_name}-worker-${count.index + 1}-data"
  size      = var.worker_volumes
  server_id = hcloud_server.workers[count.index].id
  format    = "ext4"
  location  = var.region

  labels = merge(local.worker_labels, {
    purpose = "persistent-data"
  })

  lifecycle {
    prevent_destroy = true
  }
}
