# Cloud-Init Deep Dive

## Overview

Cloud-init is the backbone of our automated deployment. It replaces traditional SSH provisioners by allowing servers to self-configure on first boot.

## Why Cloud-Init?

**Traditional Approach (SSH Provisioners)**:
```
Terraform → Create Server → SSH In → Run Commands
Problem: Requires unencrypted SSH keys, brittle connections
```

**Our Approach (Cloud-Init)**:
```
Terraform → Create Server + User Data → Server Self-Configures
Benefit: Encrypted SSH keys work, no connection management
```

## Cloud-Init Lifecycle on Control Plane Nodes

### Phase 1: Package Installation (30 seconds)

```yaml
packages:
  - curl          # API calls, RKE2 installation
  - jq            # JSON parsing
  - qemu-guest-agent  # Hetzner integration
  - iptables-persistent  # Firewall persistence
```

### Phase 2: File Creation (immediate)

Cloud-init writes configuration files to disk:

| File | Purpose | Content |
|------|---------|---------|
| `/etc/rancher/rke2/config.yaml` | RKE2 main config | Cluster settings, TLS-SAN |
| `/etc/rancher/rke2/config.yaml.d/90-first-server.yaml` | First CP init | `cluster-init: true` |
| `/etc/rancher/rke2/config.yaml.d/90-join-server.yaml` | Other CP join | `server: https://first-cp:9345` |
| `/var/lib/rancher/rke2/server/manifests/hcloud-secret.yaml` | HCCM auth | Hetzner API token + network ID |
| `/var/lib/rancher/rke2/server/manifests/hcloud-cloud-controller-manager.yaml` | HCCM deploy | HelmChart manifest |
| `/var/lib/rancher/rke2/server/manifests/hcloud-csi.yaml` | CSI deploy | HelmChart manifest |

### Phase 3: RKE2 Installation (2-3 minutes)

```bash
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="v1.29.3+rke2r1" sh -
systemctl enable rke2-server
systemctl start rke2-server
```

### Phase 4: Wait for RKE2 Ready (2-5 minutes)

The `wait-for-rke2.sh` script:

```bash
# Wait for kubeconfig to exist
until [ -f /etc/rancher/rke2/rke2.yaml ]; do sleep 5; done

# Wait for API server to respond
until kubectl get nodes &>/dev/null; do sleep 5; done

# Setup kubectl for root user
mkdir -p /root/.kube
cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
```

### Phase 5: Node Labeling

After RKE2 is ready, cloud-init labels the node:

```bash
kubectl label node <node-name> node.kubernetes.io/instance-type=<type> --overwrite
kubectl label node <node-name> topology.kubernetes.io/region=<region> --overwrite
```

## Cloud-Init Lifecycle on Worker Nodes

Workers have a simpler lifecycle:

1. **Install packages** (same as CP)
2. **Write RKE2 agent config**:
   ```yaml
   server: https://<server-url>:9345   # DNS name if configured, else first CP IP
   token: <cluster-token>
   ```
3. **Install RKE2 agent**:
   ```bash
   curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" INSTALL_RKE2_VERSION="..." sh -
   ```
4. **Start agent**:
   ```bash
   systemctl enable rke2-agent
   systemctl start rke2-agent
   ```

## TLS-SAN and DNS Configuration

The RKE2 TLS-SAN list includes:
- Node's private IP
- First control plane private IP
- **Your DNS name** (if `cluster_api_dns` is set)

```yaml
tls-san:
  - 10.0.1.10
  - 10.0.1.11
  - k8s.example.com   # <-- Your DNS name goes here
```

**Important**: The DNS name is baked into the certificate at installation time. If you add DNS later, you must update `cluster_api_dns` and recreate the nodes.

## Template Variables

Cloud-init is processed by Terraform's `templatefile()`. These variables are injected:

### Control Plane Template Variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `rke2_version` | `var.rke2_version` | Install specific RKE2 version |
| `rke2_token` | Auto-generated or `var.rke2_token` | Cluster registration token |
| `node_name` | Generated from `var.cluster_name` | Kubernetes node name |
| `cluster_name` | `var.cluster_name` | Resource naming prefix |
| `is_first_server` | `count.index == 0` | First CP gets `cluster-init: true` |
| `first_control_plane_ip` | `cidrhost(var.cp_subnet, 10)` | IP for joining |
| `cluster_api_dns` | `var.cluster_api_dns` | DNS name for TLS-SAN |
| `private_ip` | Calculated from subnet | Node's private IP |
| `cni` | `var.rke2_cni` | CNI plugin selection |
| `enable_hccm` | `var.enable_hccm` | Enable HCCM installation |
| `hcloud_token` | `var.hcloud_token` | Hetzner API token for HCCM |

### Worker Template Variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `rke2_version` | `var.rke2_version` | Install specific RKE2 version |
| `rke2_token` | Same as CP | Cluster registration token |
| `server_url` | `var.cluster_api_dns` or first CP IP | Server URL for joining |
| `first_control_plane_ip` | First CP IP | Fallback server URL |
| `server_type` | `var.worker_server_type` | Node label |

## Monitoring Cloud-Init

### Check Status

```bash
# SSH to a node
ssh root@<NODE_IP>

# Check cloud-init status
cat /var/lib/cloud/instance/boot-finished
cat /var/log/cloud-init-output.log

# Check RKE2 status
systemctl status rke2-server  # CP
systemctl status rke2-agent   # Worker
```

### Common Log Messages

```
# Success
"RKE2 is ready!"
"Setup complete. Kubernetes version: ..."
"Token has been wiped from disk."

# RKE2 waiting
"Waiting for kubeconfig..."
"Waiting for API server..."
```

## Customizing Cloud-Init

### Add Custom Scripts

Edit `cloud-init-control-plane.yaml`:

```yaml
write_files:
  # Your custom script
  - path: /usr/local/bin/my-custom-script.sh
    content: |
      #!/bin/bash
      echo "Running custom setup..."
      # Your logic here
    owner: root:root
    permissions: '0755'

runcmd:
  # Run after everything else
  - /usr/local/bin/my-custom-script.sh
```

### Add Custom RKE2 Options

Add to the `config.yaml` template in `cloud-init-control-plane.yaml`:

```yaml
  - path: /etc/rancher/rke2/config.yaml
    content: |
      # ... existing options ...
      kube-apiserver-arg:
        - "audit-log-path=/var/log/audit.log"
        - "audit-policy-file=/etc/rancher/rke2/audit.yaml"
```

## Troubleshooting Cloud-Init

### Cloud-init Failed

```bash
# Check cloud-init final status
cat /var/lib/cloud/instance/status.json

# Check for errors
grep -i error /var/log/cloud-init-output.log

# Re-run cloud-init (NOT recommended for production)
cloud-init clean --logs
cloud-init init
cloud-init modules
```

### RKE2 Not Starting

```bash
# Check logs
journalctl -u rke2-server -n 50

# Check config syntax
cat /etc/rancher/rke2/config.yaml

# Check if port 6443 is listening
ss -tlnp | grep 6443

# Manual start for debugging
/usr/local/bin/rke2 server --debug
```

## Security Considerations

### HCCM Secret

- `/var/lib/rancher/rke2/server/manifests/hcloud-secret.yaml`: Contains main token
- This is **kept** in the cluster (HCCM needs it to manage nodes)
- Secured by Kubernetes RBAC

### CSI Secret

- `/var/lib/rancher/rke2/server/manifests/hcloud-csi-encryption.yaml`: Encryption passphrase
- Kept in the cluster
- Used for encrypted volume provisioning
