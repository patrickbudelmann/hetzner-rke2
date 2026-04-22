# Examples

This document provides complete examples for deploying clusters with different configurations.

## Table of Contents

1. [Minimal Development Cluster](#minimal-development-cluster)
2. [Small Production Cluster](#small-production-cluster)
3. [High-Availability Production Cluster](#high-availability-production-cluster)
4. [Multi-Zone Deployment](#multi-zone-deployment)
5. [CIS-Hardened Cluster](#cis-hardened-cluster)
6. [Cost-Optimized Testing](#cost-optimized-testing)

---

## Minimal Development Cluster

For local development and testing. Single CP node, 1 worker, minimal resources.

### terraform.tfvars

```hcl
# Required
hcloud_token = "your-main-token"
ssh_public_key = "ssh-ed25519 AAA..."
allowed_ssh_cidr = ["YOUR.IP/32"]

# Minimal config
cluster_name = "dev-cluster"
environment  = "dev"

# Single CP node (no HA)
control_plane_count       = 1
control_plane_server_type = "cpx11"  # Smallest available

# Single worker
worker_count       = 1
worker_server_type = "cpx11"

# Small network
network_cidr         = "10.0.0.0/16"
control_plane_subnet = "10.0.1.0/24"
worker_subnet        = "10.0.2.0/24"

# Disable unnecessary features for dev
enable_backups  = false
enable_hccm     = false   # Skip HCCM for faster startup
enable_csi_driver = false  # Skip CSI for dev
enable_auto_updates = false # Faster startup

# Latest RKE2
rke2_version = "v1.29.3+rke2r1"
rke2_cni     = "cilium"
```

### Estimated Cost

- CP node (cpx11): ~€3.50/month
- Worker (cpx11): ~€3.50/month
- **Total: ~€7/month**

---

## Small Production Cluster

For small production workloads. 3 CP nodes for HA, 2 workers.

### terraform.tfvars

```hcl
# Credentials
hcloud_token = "your-main-token"
ssh_public_key = "ssh-ed25519 AAA..."
allowed_ssh_cidr = ["YOUR.IP/32"]

# Cluster
cluster_name = "prod-small"
environment  = "prod"
region       = "fsn1"

# 3 CP nodes for etcd quorum
control_plane_count       = 3
control_plane_server_type = "cpx21"  # 2 vCPU, 4GB RAM

# 2 workers
worker_count       = 2
worker_server_type = "cpx31"  # 4 vCPU, 8GB RAM

# Network
network_cidr         = "10.0.0.0/16"
control_plane_subnet = "10.0.1.0/24"
worker_subnet        = "10.0.2.0/24"

# Production features
enable_backups      = true
backup_window       = "04:00"
enable_hccm         = true
enable_csi_driver   = true
enable_auto_updates = true

# HCCM and CSI versions
hccm_version       = "v1.20.0"
csi_driver_version = "v2.7.0"

# RKE2
rke2_version = "v1.29.3+rke2r1"
rke2_cni     = "cilium"

# Load balancer
lb_type      = "lb11"
lb_algorithm = "round_robin"
```

### Estimated Cost

- CP nodes (cpx21 × 3): ~€30/month
- Workers (cpx31 × 2): ~€40/month
- LB (lb11): ~€5/month
- **Total: ~€75/month**

---

## High-Availability Production Cluster

For production with high availability and larger workloads.

### terraform.tfvars

```hcl
# Credentials
hcloud_token = "your-main-token"
ssh_public_key = "ssh-ed25519 AAA..."
allowed_ssh_cidr = ["YOUR.IP/32"]

# Cluster
cluster_name = "prod-ha"
environment  = "prod"
region       = "fsn1"

# 5 CP nodes (maximum HA)
control_plane_count       = 5
control_plane_server_type = "cpx41"  # 8 vCPU, 16GB RAM

# 4 workers
worker_count       = 4
worker_server_type = "cpx41"  # 8 vCPU, 16GB RAM

# Extra volumes for workers
worker_volumes = 100  # 100GB per worker

# Network
network_cidr         = "10.0.0.0/16"
control_plane_subnet = "10.0.1.0/24"
worker_subnet        = "10.0.2.0/24"

# Production features
enable_backups      = true
backup_window       = "04:00"
enable_hccm         = true
enable_csi_driver   = true
enable_auto_updates = true

# CIS hardening
rke2_cis_profile = "cis"

# HCCM and CSI
hccm_version       = "v1.20.0"
csi_driver_version = "v2.7.0"

# RKE2 with snapshots
rke2_version = "v1.29.3+rke2r1"
rke2_cni     = "cilium"

# Larger LB
lb_type      = "lb21"
lb_algorithm = "round_robin"

# Node labels
control_plane_labels = {
  "topology.kubernetes.io/zone" = "eu-central"
}

worker_labels = {
  "workload-type" = "general"
}

# Allow NodePort access from VPN
additional_allowed_cidrs = ["10.100.0.0/16"]
```

### Estimated Cost

- CP nodes (cpx41 × 5): ~€200/month
- Workers (cpx41 × 4): ~€160/month
- Volumes (100GB × 4): ~€16/month
- LB (lb21): ~€15/month
- **Total: ~€391/month**

---

## Cost-Optimized Testing

For CI/CD pipelines and temporary testing.

### terraform.tfvars

```hcl
# Credentials
hcloud_token = "your-main-token"
ssh_public_key = "ssh-ed25519 AAA..."
allowed_ssh_cidr = ["YOUR.IP/32"]

# Test cluster
cluster_name = "test-cluster"
environment  = "dev"

# Minimal resources
control_plane_count       = 1
control_plane_server_type = "cpx11"

worker_count       = 1
worker_server_type = "cpx11"

# Disable everything for speed
enable_backups      = false
enable_hccm         = false
enable_csi_driver   = false
enable_auto_updates = false

# Use older/smaller image if available
control_plane_image = "ubuntu-24.04"
worker_image        = "ubuntu-24.04"

# Flannel instead of Cilium (lighter)
rke2_cni = "flannel"
```

### Estimated Cost

- CP node (cpx11): ~€3.50/month
- Worker (cpx11): ~€3.50/month
- **Total: ~€7/month**

---

## CIS-Hardened Cluster

For compliance-heavy environments.

### terraform.tfvars

```hcl
# Credentials
hcloud_token = "your-main-token"
ssh_public_key = "ssh-ed25519 AAA..."
allowed_ssh_cidr = ["YOUR.OFFICE.IP/32"]

# Secure cluster
cluster_name = "prod-secure"
environment  = "prod"

# 3 CP nodes
control_plane_count       = 3
control_plane_server_type = "cpx31"

# 2 workers
worker_count       = 2
worker_server_type = "cpx41"

# CIS hardening (required for compliance)
rke2_cis_profile = "cis"

# Enable ALL security features
enable_backups         = true
backup_window          = "04:00"
enable_hccm            = true
enable_csi_driver      = true
enable_auto_updates    = true
enable_nodeport_access = false  # Don't expose NodePorts

# Restrict SSH further
# Only allow from VPN/bastion
additional_allowed_cidrs = []

# RKE2 settings
rke2_version          = "v1.29.3+rke2r1"
rke2_cni              = "cilium"
rke2_etcd_snapshot_interval  = 3
rke2_etcd_snapshot_retention = 48

# HCCM and CSI
hccm_version       = "v1.20.0"
csi_driver_version = "v2.7.0"
```

### Post-Deployment Security Steps

```bash
# 1. Verify CIS compliance
kubectl get nodes -o json | jq '.items[].metadata.labels'

# 2. Check etcd user exists on CP nodes
ssh root@<CP_IP> "id etcd"

# 3. Verify sysctl settings
ssh root@<CP_IP> "sysctl kernel.keys.root_maxbytes"

# 4. Check directory permissions
ssh root@<CP_IP> "stat /etc/rancher/rke2"
```

---

## Region-Specific Deployment

### Deploy in US East (Ashburn)

```hcl
region       = "ash"
network_zone = "us-east"

# Use same config as production
cluster_name = "prod-us"
environment  = "prod"

control_plane_count       = 3
control_plane_server_type = "cpx21"
worker_count              = 2
worker_server_type        = "cpx31"
```

### Multi-Zone (Not Yet Supported)

Note: Hetzner Cloud networks span multiple locations within the same zone, but you cannot span across zones (eu-central to us-east).

For true multi-zone, you'd need:
- Separate deployments per zone
- VPN or transit gateway between zones
- Custom federation or service mesh

---

## Application Deployment Examples

After cluster is up, here are common workloads:

### Deploy Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml
```

### Deploy cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
```

### Deploy Monitoring (Prometheus + Grafana)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

### Deploy with Hetzner Load Balancer

```yaml
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    load-balancer.hetzner.cloud/name: "my-service-lb"
    load-balancer.hetzner.cloud/location: "fsn1"
    load-balancer.hetzner.cloud/type: "lb11"
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
EOF
```

---

## Environmental Configuration Patterns

### Dev Environment

```hcl
cluster_name = "dev-01"
environment  = "dev"

# Minimal resources
control_plane_count = 1
worker_count       = 1

# Disable backups for speed
enable_backups = false

# Latest RKE2
rke2_version = "v1.29.3+rke2r1"

# Labels
control_plane_labels = {
  "environment" = "development"
}
```

### Staging Environment

```hcl
cluster_name = "staging-01"
environment  = "staging"

# Moderate resources
control_plane_count = 3
worker_count       = 2

# Enable features
enable_backups = true
enable_hccm    = true

# Labels
worker_labels = {
  "workload-type" = "staging"
}
```

### Production Environment

```hcl
cluster_name = "prod-01"
environment  = "prod"

# Full HA
control_plane_count = 3
worker_count       = 4

# All features
enable_backups    = true
enable_hccm       = true
enable_csi_driver = true

# CIS hardening
rke2_cis_profile = "cis"

# Taints on CP
control_plane_taints = [
  "node-role.kubernetes.io/control-plane:NoSchedule"
]

# No taints on workers
worker_taints = []
```

---

## Tips for Choosing Configuration

### Server Types

| Type | vCPU | RAM | Disk | Use Case |
|------|------|-----|------|----------|
| cpx11 | 2 | 4GB | 40GB | Dev, testing |
| cpx21 | 4 | 8GB | 80GB | Small production |
| cpx31 | 8 | 16GB | 160GB | Production workloads |
| cpx41 | 16 | 32GB | 240GB | Large workloads |
| ccx32 | 8 | 32GB | 160GB | Memory-intensive |

### Control Plane Sizing

- **1 node**: Development only (no HA)
- **3 nodes**: Minimum for production HA
- **5 nodes**: Maximum etcd performance
- **7 nodes**: Only for very large clusters

### Worker Sizing

- **2 workers**: Minimum for production
- **4+ workers**: For high availability and workload distribution
- **Autoscaling**: Add workers as needed

### Budget Considerations

| Environment | Monthly Cost | Nodes |
|-------------|-------------|-------|
| Development | €7-15 | 1-2 |
| Small Prod | €40-80 | 3-4 |
| Medium Prod | €100-200 | 5-6 |
| Large Prod | €300-500 | 7-10 |

---

## See Also

- [Deployment Guide](deployment-guide.md) - Step-by-step deployment instructions
- [Network Architecture](network.md) - Network configuration details
- [Security Guide](security.md) - Security best practices
- [Troubleshooting](troubleshooting.md) - Common issues and solutions
