# Security Guide

## Overview

This project implements a **security-first architecture** with these key principles:

- No SSH provisioners during deployment (encrypted keys work)
- Temporary API tokens for cloud-init (wiped after use)
- Minimal WAN exposure (private network for all internal traffic)
- Firewall rules with strict port restrictions
- Optional CIS hardening for production environments

## API Token Management

### The Two-Token Strategy

We use two Hetzner API tokens with different purposes:

#### Token A: Main Token (`hcloud_token`)
- **Used for**: Terraform resource provisioning
- **Lifespan**: Long-term (do NOT revoke after deployment)
- **Location**: Your local machine (terraform.tfvars)
- **Scope**: Full project access (creates servers, networks, LBs)

```hcl
# terraform.tfvars
hcloud_token = "your-main-token-here"
```

#### Token B: Temporary Token (`hcloud_token_cloudinit`)
- **Used for**: Cloud-init LB discovery only (runs inside CP nodes)
- **Lifespan**: Temporary (revoke after deployment!)
- **Location**: Written to CP node disk, wiped after use
- **Risk**: Lower if properly managed and revoked

```hcl
# terraform.tfvars
hcloud_token_cloudinit = "your-temporary-token-here"
```

### Why Two Tokens?

Hetzner does NOT support API tokens with different permission levels (no read-only tokens).
Every token has full project access.

The two-token strategy provides:
- **Isolation**: Compromise of temp token doesn't affect main token
- **Revocability**: Temp token is immediately revoked after deployment
- **Auditing**: Easy to identify which token was used where
- **Limited exposure**: Temp token only exists on disk for ~10 minutes

### Token Lifecycle

```
Before Deployment
│
├── Hetzner Console → Create "terraform-main" token
│   └── Store in: hcloud_token variable
│
├── Hetzner Console → Create "terraform-temp-lb-discovery" token
│   └── Store in: hcloud_token_cloudinit variable
│
During Deployment
│
├── Terraform uses main token to create resources
│
└── CP nodes receive temp token via cloud-init
    └── Token written to: /etc/rancher/rke2/.hcloud-token
│
After LB Discovered
│
└── CP node script detects LB IP
    └── Updates RKE2 config
    └── Restarts RKE2
    └── WIPES token file → /etc/rancher/rke2/.hcloud-token deleted
│
After Deployment (CRITICAL!)
│
└── Hetzner Console → Revoke "terraform-temp-lb-discovery" token
    └── Zero residual risk
```

### Creating the Temporary Token

#### Method 1: Hetzner Cloud Console (Recommended)

1. Log in to [Hetzner Cloud Console](https://console.hetzner.cloud/)
2. Select your project
3. Navigate to **Security** → **API Tokens**
4. Click **Generate API Token**
5. Name it: `rke2-temp-<cluster-name>`
6. Copy the token value
7. Paste into `terraform.tfvars`

#### Method 2: Using hcloud CLI (If Installed)

```bash
# Install hcloud CLI (if not already)
brew install hcloud  # macOS
# or
apt install hcloud   # Debian/Ubuntu

# Login
hcloud context create my-project

# Create token
hcloud token create --name rke2-temp-production
```

### Revoking the Temporary Token

**This is CRITICAL - do not skip!**

#### Via Console:
1. Log in to [Hetzner Cloud Console](https://console.hetzner.cloud/)
2. Navigate to **Security** → **API Tokens**
3. Find your temporary token (`rke2-temp-*`)
4. Click **Delete** or **Revoke**

#### Via hcloud CLI:
```bash
hcloud token list
hcloud token delete <token-id>
```

#### Via Terraform Output:
```bash
terraform output token_revocation_reminder
```

### Verifying Token Was Wiped

```bash
# SSH to a control plane node
ssh -i ~/.ssh/id_ed25519 root@<CP_IP>

# Check token file is gone
ls -la /etc/rancher/rke2/.hcloud-token
# Expected: No such file or directory

# Check discovery log
head -20 /var/log/rke2-tls-discovery.log
# Expected: Lines showing "Wiping Hetzner token from disk..."
```

### Token Without Temporary Token (Fallback)

If you don't provide `hcloud_token_cloudinit`, the main `hcloud_token` is used. This works but:
- ⚠️ Your main token is exposed on CP nodes
- ⚠️ Cannot revoke it without breaking HCCM/CSI
- ⚠️ Higher security risk

**Recommendation**: Always use the two-token strategy for production!

## Firewall Configuration

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
2. **Kubernetes API (6443)**: Exposed to internet but only via Load Balancer
3. **etcd (2379-2380)**: Private network only - never exposed
4. **Kubelet (10250)**: Private network only - prevents unauthorized access
5. **Internal traffic**: Full access within private network (10.0.0.0/16)

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

- [ ] Created separate main and temporary Hetzner tokens
- [ ] Restricted `allowed_ssh_cidr` to your IP only
- [ ] Enabled CIS hardening (`rke2_cis_profile = "cis"`)
- [ ] Enabled automatic updates
- [ ] Enabled etcd backups
- [ ] Enabled CSI driver for encrypted volumes
- [ ] Configured `additional_allowed_cidrs` for VPN/office (if needed)
- [ ] Set `cluster_name` to something random (not "rke2")
- [ ] Enabled `enable_nodeport_access` only if required
- [ ] Verified node taints are appropriate (CP nodes should have taints)

After deployment:

- [ ] Revoked the temporary Hetzner token
- [ ] Verified token was wiped from CP nodes
- [ ] Retrieved and secured kubeconfig
- [ ] Verified all nodes are `Ready`
- [ ] Checked HCCM and CSI are running
- [ ] Reviewed `terraform output token_revocation_reminder`
