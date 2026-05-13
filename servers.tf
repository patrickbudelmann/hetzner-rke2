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
    enable_s3_csi             = var.enable_s3_csi_driver
    s3_csi_version            = var.s3_csi_version
    s3_endpoint_url           = local.s3_endpoint
    s3_region                 = local.s3_region
    s3_access_key_id          = var.s3_access_key_id
    s3_secret_access_key      = var.s3_secret_access_key
    enable_cluster_autoscaler = var.enable_cluster_autoscaler
    autoscaler_min_nodes      = var.autoscaler_min_nodes
    autoscaler_max_nodes      = var.autoscaler_max_nodes
    autoscaler_node_type      = var.autoscaler_node_type
    autoscaler_node_pool_name = var.autoscaler_node_pool_name
    autoscaler_node_group     = local.autoscaler_node_group
    autoscaler_cluster_config = local.autoscaler_cluster_config
    enable_monitoring        = var.enable_monitoring
    monitoring_version       = var.monitoring_version
    enable_ingress           = var.enable_ingress
    enable_cert_manager      = var.enable_cert_manager
    cert_manager_version    = var.cert_manager_version
    enable_etcd_s3_backup   = var.enable_etcd_s3_backup
    etcd_s3_bucket          = var.etcd_s3_bucket
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
# Node Drain on Destroy (Control Plane)
# =============================================================================
resource "null_resource" "drain_control_plane" {
  count = var.control_plane_count

  triggers = {
    server_id = hcloud_server.control_plane[count.index].id
  }

  provisioner "remote-exec" {
    when = destroy

    inline = [
      "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml",
      "kubectl drain ${var.cluster_name}-cp-${count.index + 1} --ignore-daemonsets --delete-emptydir-data --force --timeout=120s || true"
    ]
  }

  connection {
    type        = "ssh"
    host        = hcloud_server.control_plane[count.index].ipv4_address
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    timeout     = "2m"
  }

  depends_on = [
    hcloud_server.control_plane,
  ]
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

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

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

# =============================================================================
# Node Drain on Destroy (Workers)
# =============================================================================
resource "null_resource" "drain_workers" {
  count = var.worker_count

  triggers = {
    server_id = hcloud_server.workers[count.index].id
  }

  provisioner "remote-exec" {
    when = destroy

    inline = [
      "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml",
      "kubectl drain ${var.cluster_name}-worker-${count.index + 1} --ignore-daemonsets --delete-emptydir-data --force --timeout=120s || true"
    ]
  }

  # Run drain command on first control plane node (has kubectl access)
  connection {
    type        = "ssh"
    host        = hcloud_server.control_plane[0].ipv4_address
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    timeout     = "2m"
  }

  depends_on = [
    hcloud_server.workers,
    hcloud_server.control_plane,
  ]
}
