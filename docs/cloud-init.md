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
  - jq            # JSON parsing (Hetzner API response)
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
| `/etc/rancher/rke2/.hcloud-token` | **TEMP token** | For LB discovery |

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

### Phase 5: LB Discovery Script (Background)

This is where the magic happens! The script runs in the background via `nohup`.

```bash
nohup /usr/local/bin/discover-lb-and-update-tls.sh > /var/log/rke2-tls-discovery.nohup 2>&1 &
```

#### Discovery Script Flow

```
1. Check if token file exists
   └── If not: exit (already wiped or never provided)

2. Read token from /etc/rancher/rke2/.hcloud-token

3. Wait for RKE2 to be stable
   ├── Check kubeconfig exists
   └── Check kubectl get nodes works

4. Poll Hetzner API (30 retries, 20 seconds)
   └── curl -H "Authorization: Bearer $TOKEN" https://api.hetzner.cloud/v1/load_balancers

5. Parse JSON response with jq
   └── Extract: .load_balancers[] | select(.name == "cluster-name-api-lb") | .public_net.ipv4.ip

6. If LB found:
   ├── Check if IP already in TLS-SAN
   │   └── If yes: skip update
   ├── Backup config: cp config.yaml config.yaml.bak.<timestamp>
   ├── Update TLS-SAN with LB IP
   └── Restart RKE2: systemctl restart rke2-server

7. If LB not found (timeout):
   └── Log warning, continue with basic config

8. ALWAYS wipe token file
   └── rm -f /etc/rancher/rke2/.hcloud-token
```

#### Discovery Timing

```
Start: ~30 seconds after RKE2 is ready
Retry interval: 20 seconds
Max retries: 30 (10 minutes total)
Expected discovery: 2-5 minutes (after LB is created)
RKE2 restart: ~15-30 seconds
Total additional time: ~3-6 minutes
```

## Cloud-Init Lifecycle on Worker Nodes

Workers have a simpler lifecycle:

1. **Install packages** (same as CP)
2. **Write RKE2 agent config**:
   ```yaml
   server: https://first-cp-ip:9345
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
5. **No LB discovery** (workers don't need it)

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
| `private_ip` | Calculated from subnet | Node's private IP |
| `cni` | `var.rke2_cni` | CNI plugin selection |
| `enable_hccm` | `var.enable_hccm` | Enable HCCM installation |
| `hcloud_token_cloudinit` | `local.hcloud_token_cloudinit` | **TEMP token for LB discovery** |

### Worker Template Variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `rke2_version` | `var.rke2_version` | Install specific RKE2 version |
| `rke2_token` | Same as CP | Cluster registration token |
| `first_control_plane_ip` | `cidrhost(var.cp_subnet, 10)` | Server URL |
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

# Check LB discovery log
cat /var/log/rke2-tls-discovery.log

# Check nohup output
cat /var/log/rke2-tls-discovery.nohup
```

### Common Log Messages

```
# Success
"Found Load Balancer IP: 91.99.113.133"
"Updating RKE2 TLS-SAN with LB IP: 91.99.113.133"
"SUCCESS: RKE2 restarted with new TLS certificate..."
"Token has been wiped from disk."

# Timeout (normal if LB takes >10 min)
"WARNING: Could not discover LB after 30 attempts."
"Token has been wiped from disk."

# Already done
"LB IP 91.99.113.133 already in TLS-SAN. Token wiped."
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

### Token Not Wiped

```bash
# Check if file exists
ls -la /etc/rancher/rke2/.hcloud-token

# Check discovery log for errors
tail -50 /var/log/rke2-tls-discovery.log

# Manual wipe (emergency only)
rm -f /etc/rancher/rke2/.hcloud-token
```

## Security Considerations

### Token Files

- `/etc/rancher/rke2/.hcloud-token`: **Should be deleted** after LB discovery
- Verify deletion: `ls -la /etc/rancher/rke2/.hcloud-token` (should not exist)

### HCCM Secret

- `/var/lib/rancher/rke2/server/manifests/hcloud-secret.yaml`: Contains main token
- This is **kept** in the cluster (HCCM needs it to manage nodes)
- Secured by Kubernetes RBAC

### CSI Secret

- `/var/lib/rancher/rke2/server/manifests/hcloud-csi-encryption.yaml`: Encryption passphrase
- Kept in the cluster
- Used for encrypted volume provisioning
