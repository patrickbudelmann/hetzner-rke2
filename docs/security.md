# Security Guide

## Overview

This project implements a **security-first architecture** with these key principles:

- No SSH provisioners during deployment (encrypted keys work)
- Minimal WAN exposure (private network for all internal traffic)
- Firewall rules with strict port restrictions
- DNS-based API endpoint (stable TLS certificate)
- Optional CIS hardening for production environments
- Workers without public IPs (jump host access only)
- File-based secret injection (no inline secrets in manifests)
- Kubelet authentication hardened (anonymous-auth=false)

## Secrets Management

### File-Based Secret Injection

This project uses a **file-based approach** for injecting secrets into the cluster, avoiding inline secrets in Terraform manifests:

1. **Secrets stored as files** on your local machine (e.g., `secrets/hcloud-token.txt`)
2. **Cloud-init reads files** during server bootstrap
3. **Kubernetes manifests reference files** via templating
4. **No secrets in Terraform state** or version control

**Example pattern:**

```bash
# Create secrets directory
mkdir -p secrets

# Store secrets as files
echo "your-token-here" > secrets/hcloud-token.txt
chmod 600 secrets/hcloud-token.txt

# Cloud-init reads and injects into manifest
# /var/lib/rancher/rke2/server/manifests/hcloud-secret.yaml
```

**Benefits:**
- Secrets never appear in Terraform plan/apply output
- No secrets in git history
- Easy rotation (update file, re-apply)
- Compatible with secret management tools (Vault, SOPS, etc.)

### API Token Management

#### Main Token (`hcloud_token`)

The Hetzner Cloud API token used by Terraform to create resources (servers, networks, load balancers, firewalls):

- **Used for**: Terraform resource provisioning AND HCCM/CSI cluster integration
- **Lifespan**: Long-term (do NOT revoke after deployment - HCCM needs it!)
- **Location**: Your local machine (`terraform.tfvars`) and inside the cluster (HCCM Secret)
- **Scope**: Full project access

```hcl
# terraform.tfvars
hcloud_token = "your-main-token-here"
```

**Important**: This token is stored in the Kubernetes cluster as a Secret for HCCM/CSI to manage resources. Do NOT revoke it or HCCM will break.

### Token Storage in Cluster

The token is stored in the cluster by cloud-init via a Kubernetes manifest:

```yaml
# /var/lib/rancher/rke2/server/manifests/hcloud-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: hcloud
  namespace: kube-system
type: Opaque
stringData:
  token: "<your-token>"
  network: "<network-id>"
```

This Secret is secured by Kubernetes RBAC and only accessible to HCCM and CSI pods.

### Token Rotation

If you need to rotate the token:

1. Create a new token in Hetzner Console
2. Update `terraform.tfvars` with the new token
3. Update the Secret in the cluster:
   ```bash
   kubectl patch secret hcloud -n kube-system \
     --type='json' \
     -p='[{"op": "replace", "path": "/data/token", "value":"'<base64-encoded-new-token>'"}]'
   ```
4. Restart HCCM and CSI pods
5. Revoke the old token in Hetzner Console

## DNS-Based API Endpoint

### Control Plane Firewall Rules

| Direction | Protocol | Port | Source | Purpose |
|-----------|----------|------|--------|---------|
| Inbound | TCP | 22 | Your IP only | SSH access |
| Inbound | ICMP | - | Any | Ping/basic connectivity |
| Inbound | TCP | 6443 | Any | Kubernetes API (via LB) |
| Inbound | TCP | 9345 | Private net | RKE2 supervisor |
| Inbound | TCP | 2379-2380 | Private net | etcd peer-to-peer |
| Inbound | TCP | 10250 | Private net | Kubelet API |
| Inbound | TCP | 10257 | Private net | kube-controller-manager |
| Inbound | TCP | 10259 | Private net | kube-scheduler |
| Inbound | UDP | 8472 | Private net | CNI VXLAN |
| Inbound | UDP | 51820-51821 | Private net | WireGuard (Cilium) |
| Inbound | TCP | 1-65535 | Private net | All TCP within network |
| Inbound | UDP | 1-65535 | Private net | All UDP within network |

### Worker Firewall Rules

| Direction | Protocol | Port | Source | Purpose |
|-----------|----------|------|--------|---------|
| Inbound | TCP | 22 | Your IP only | SSH access |
| Inbound | ICMP | - | Any | Ping |
| Inbound | TCP | 30000-32767 | Configurable | NodePort services |
| Inbound | UDP | 8472 | Private net | CNI VXLAN |
| Inbound | UDP | 51820-51821 | Private net | WireGuard |
| Inbound | TCP | 1-65535 | Private net | All TCP within network |
| Inbound | UDP | 1-65535 | Private net | All UDP within network |

### Key Security Points

1. **SSH (22/tcp)**: Restricted to your IP only - never open to 0.0.0.0/0
2. **Kubernetes API (6443)**: Exposed to internet but only via Load Balancer, restricted to private network + `additional_allowed_cidrs`
3. **etcd (2379-2380)**: Private network only - never exposed
4. **Kubelet (10250)**: Private network only - prevents unauthorized access
5. **Internal traffic**: Full access within private network (10.0.0.0/16)
6. **Workers have NO public IPs**: All worker traffic flows through private network

### Firewall Hardening

#### API Server (6443) Restriction

The Kubernetes API server port is **restricted to the private network** by default, with optional additional CIDRs:

```hcl
# terraform.tfvars
additional_allowed_cidrs = [
  "10.0.100.0/24",  # Your VPN network
  "203.0.113.0/24", # Office network
]
```

This means:
- API traffic from internet must go through the Load Balancer
- Direct API access to control plane nodes is blocked
- Only private network + explicitly allowed CIDRs can reach 6443 directly

#### Worker Node Isolation

Worker nodes have **no public IPs** by design:

- **Benefit**: Attackers cannot directly target workers from internet
- **SSH Access**: Requires jump host through control plane
- **Pattern**: `ssh -J root@<CP_PUBLIC_IP> root@<WORKER_PRIVATE_IP>`
- **NodePort Services**: Still accessible via `additional_allowed_cidrs` if enabled

### Kubelet Authentication

The kubelet is hardened with **anonymous authentication disabled**:

```yaml
# RKE2 configuration (automatic)
kubelet-arg:
  - "anonymous-auth=false"
  - "authentication-token-webhook=true"
```

**What this prevents:**
- Unauthenticated requests to kubelet API
- Unauthorized container exec via kubelet
- Service account token enumeration

**Impact:**
- All kubelet requests require authentication
- Kubernetes API server authenticates via webhook
- Metrics scrapers need proper service accounts

### Control Plane Bind Addresses

Control plane components bind to **127.0.0.1** where possible:

```yaml
# kube-controller-manager
bind-address: 127.0.0.1

# kube-scheduler
bind-address: 127.0.0.1
```

**Security benefit:**
- These components only accept local connections
- Cannot be accessed directly from network
- Must go through API server (proper RBAC)

**Exceptions:**
- etcd binds to private network IP (for peer communication)
- API server binds to private network IP (for kubelet communication)

## Network Security

### Private Network Isolation

All internal cluster communication happens over the private network:
- etcd replication
- kubelet to API server
- CNI overlay (pod-to-pod)
- CSI driver communication

### Public Exposure

Only three things are exposed to the internet:
1. **SSH (22)** - Restricted to your IP
2. **Kubernetes API (6443)** - Via load balancer
3. **NodePort services (30000-32767)** - Optional, configurable

## CIS Hardening (Optional)

Enable CIS hardening for production environments:

```hcl
# terraform.tfvars
rke2_cis_profile = "cis"
```

### What CIS Enables

- etcd runs as dedicated user (not root)
- Kernel parameters hardened
- Directory permissions restricted
- Service account token management
- Pod security standards

### CIS Requirements

Before enabling CIS:
```bash
# Create etcd user (required before first RKE2 start)
useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U

# Apply kernel parameters
cp /usr/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf
systemctl restart systemd-sysctl
```

Our cloud-init handles this automatically when `rke2_cis_profile` is set.

## Additional Security Recommendations

### 1. Enable Automatic Updates

```hcl
enable_auto_updates = true
```

This enables unattended-upgrades for security patches.

### 2. Enable Backups for Control Plane

```hcl
enable_backups = true
backup_window = "04:00"
```

### 3. Use Encrypted Volumes

```hcl
enable_csi_driver = true  # Enables encrypted storage class
```

### 4. Restrict API Access Further

After deployment, you can restrict `allowed_ssh_cidr` to a bastion host or VPN:

```hcl
allowed_ssh_cidr = ["10.0.100.10/32"]  # Bastion host IP
```

### 5. Network Policies

Consider adding Kubernetes Network Policies for pod-to-pod traffic:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### 6. Pod Security Standards

Enable Pod Security Standards:

```yaml
# Applied by RKE2 when CIS profile is enabled
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: PodSecurity
  configuration:
    defaults:
      enforce: "restricted"
      audit: "restricted"
      warn: "restricted"
```

## Security Checklist

Before deploying to production:

- [ ] Created Hetzner API token for Terraform
- [ ] Restricted `allowed_ssh_cidr` to your IP only
- [ ] Set `cluster_api_dns` for a stable API endpoint (strongly recommended)
- [ ] Enabled CIS hardening (`rke2_cis_profile = "cis"`)
- [ ] Enabled automatic updates
- [ ] Enabled etcd backups (or S3 backup)
- [ ] Enabled CSI driver for encrypted volumes
- [ ] Configured `additional_allowed_cidrs` for VPN/office (if needed)
- [ ] Set `cluster_name` to something random (not "rke2")
- [ ] Enabled `enable_nodeport_access` only if required
- [ ] Verified node taints are appropriate (CP nodes should have taints)
- [ ] Enabled ingress controller (`enable_ingress = true`)
- [ ] Enabled cert-manager for automatic TLS (`enable_cert_manager = true`)
- [ ] Configured S3 etcd backup for disaster recovery (optional)
- [ ] Reviewed firewall rules for least privilege

After deployment:

- [ ] Created DNS A record for `cluster_api_dns` pointing to LB IP
- [ ] Retrieved and secured kubeconfig
- [ ] Updated kubeconfig to use DNS name (or LB IP if no DNS)
- [ ] Verified all nodes are `Ready`
- [ ] Checked HCCM and CSI are running
- [ ] Verified ingress controller is running: `kubectl get pods -n ingress-nginx`
- [ ] Tested SSH jump host pattern to workers
- [ ] Confirmed kubelet anonymous-auth is disabled
- [ ] Verified control plane components bind to 127.0.0.1
