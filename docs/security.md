# Security Guide

## Overview

This project implements a **security-first architecture** with these key principles:

- No SSH provisioners during deployment (encrypted keys work)
- Minimal WAN exposure (private network for all internal traffic)
- Firewall rules with strict port restrictions
- DNS-based API endpoint (stable TLS certificate)
- Optional CIS hardening for production environments

## API Token Management

### Main Token (`hcloud_token`)

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

- [ ] Created Hetzner API token for Terraform
- [ ] Restricted `allowed_ssh_cidr` to your IP only
- [ ] Set `cluster_api_dns` for a stable API endpoint (strongly recommended)
- [ ] Enabled CIS hardening (`rke2_cis_profile = "cis"`)
- [ ] Enabled automatic updates
- [ ] Enabled etcd backups
- [ ] Enabled CSI driver for encrypted volumes
- [ ] Configured `additional_allowed_cidrs` for VPN/office (if needed)
- [ ] Set `cluster_name` to something random (not "rke2")
- [ ] Enabled `enable_nodeport_access` only if required
- [ ] Verified node taints are appropriate (CP nodes should have taints)

After deployment:

- [ ] Created DNS A record for `cluster_api_dns` pointing to LB IP
- [ ] Retrieved and secured kubeconfig
- [ ] Updated kubeconfig to use DNS name (or LB IP if no DNS)
- [ ] Verified all nodes are `Ready`
- [ ] Checked HCCM and CSI are running
