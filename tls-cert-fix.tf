# =============================================================================
# Automatic TLS Certificate Fix for Load Balancer IP
# This runs after deployment to add the LB public IP to RKE2's TLS certificate
# =============================================================================

# Null resource to fix TLS certificate after LB is created
resource "null_resource" "tls_cert_fix" {
  count = var.control_plane_count > 0 ? 1 : 0

  triggers = {
    lb_ipv4      = hcloud_load_balancer.rke2_api.ipv4
    first_cp_ip  = hcloud_server.control_plane[0].ipv4_address
    cluster_name = var.cluster_name
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    host        = hcloud_server.control_plane[0].ipv4_address
  }

  provisioner "remote-exec" {
    inline = [
      # Wait for RKE2 to be fully ready
      "echo 'Waiting for RKE2 to be ready...'",
      "until [ -f /etc/rancher/rke2/rke2.yaml ]; do sleep 5; done",
      "until /var/lib/rancher/rke2/bin/kubectl get nodes &>/dev/null; do sleep 5; done",
      "echo 'RKE2 is ready, checking TLS configuration...'",

      # Check if LB IP is already in the config
      "if grep -q '${hcloud_load_balancer.rke2_api.ipv4}' /etc/rancher/rke2/config.yaml; then",
      "  echo 'LB IP already in TLS-SAN, skipping...'",
      "  exit 0",
      "fi",

      # Backup the original config
      "cp /etc/rancher/rke2/config.yaml /etc/rancher/rke2/config.yaml.bak",

      # Create a new config with the LB IP added to tls-san
      "cat > /tmp/rke2-config-patch.yaml << 'EOF'",
      "tls-san:",
      "  - ${cidrhost(var.control_plane_subnet, 10)}",
      "  - ${cidrhost(var.load_balancer_subnet, 10)}",
      "  - ${hcloud_load_balancer.rke2_api.ipv4}",
      "EOF",

      # Extract existing config and merge with new tls-san
      "echo 'Updating RKE2 configuration with LB IP...'",
      "cat /etc/rancher/rke2/config.yaml | grep -v '^tls-san:' | grep -v '^  - ' > /tmp/config-head.yaml || true",
      "cat /tmp/config-head.yaml /tmp/rke2-config-patch.yaml > /etc/rancher/rke2/config.yaml",

      # Add back any other configuration after tls-san
      "cat /etc/rancher/rke2/config.yaml.bak | grep -A1000 '^cni:' >> /etc/rancher/rke2/config.yaml || true",

      # Show the new config
      "echo 'New RKE2 configuration:'",
      "cat /etc/rancher/rke2/config.yaml",

      # Restart RKE2 to regenerate certificates
      "echo 'Restarting RKE2 to regenerate certificates...'",
      "systemctl restart rke2-server",

      # Wait for RKE2 to come back up
      "echo 'Waiting for RKE2 to restart...'",
      "sleep 10",
      "until [ -f /etc/rancher/rke2/rke2.yaml ]; do sleep 5; done",
      "until /var/lib/rancher/rke2/bin/kubectl get nodes &>/dev/null; do sleep 5; done",

      "echo 'RKE2 restarted successfully with new TLS certificate!'",
      "echo 'LB IP ${hcloud_load_balancer.rke2_api.ipv4} is now in the certificate'",
    ]
  }

  depends_on = [
    hcloud_server.control_plane,
    hcloud_load_balancer.rke2_api,
    hcloud_load_balancer_service.kube_api,
  ]

  lifecycle {
    # Re-run if the LB IP changes
    replace_triggered_by = [
      hcloud_load_balancer.rke2_api
    ]
  }
}

# Alternative: Local-exec provisioner to update kubeconfig after TLS fix
resource "null_resource" "kubeconfig_update" {
  count = var.control_plane_count > 0 ? 1 : 0

  triggers = {
    tls_fix_id = null_resource.tls_cert_fix[0].id
    lb_ipv4    = hcloud_load_balancer.rke2_api.ipv4
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "=========================================="
      echo "TLS Certificate Fix Complete!"
      echo "=========================================="
      echo ""
      echo "The Load Balancer IP (${hcloud_load_balancer.rke2_api.ipv4}) has been added to the RKE2 TLS certificate."
      echo ""
      echo "To use the Load Balancer with kubectl:"
      echo "1. Get the kubeconfig:"
      echo "   scp root@${hcloud_server.control_plane[0].ipv4_address}:/etc/rancher/rke2/rke2.yaml ./kubeconfig.yaml"
      echo ""
      echo "2. Update to use Load Balancer IP:"
      echo "   sed -i '' 's/127.0.0.1/${hcloud_load_balancer.rke2_api.ipv4}/g' kubeconfig.yaml"
      echo ""
      echo "3. Set KUBECONFIG:"
      echo "   export KUBECONFIG=$(pwd)/kubeconfig.yaml"
      echo ""
      echo "4. Test:"
      echo "   kubectl get nodes"
      echo ""
      echo "Note: If you still get TLS errors, wait 1-2 minutes for the certificate to be fully propagated."
    EOT
  }

  depends_on = [
    null_resource.tls_cert_fix,
  ]
}
