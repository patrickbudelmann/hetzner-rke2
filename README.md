# RKE2 on Hetzner Cloud - Terraform Setup

This Terraform configuration deploys a production-ready RKE2 Kubernetes cluster on Hetzner Cloud.

## Features

- **High Availability**: Multi-node control plane with etcd clustering (odd node count for quorum)
- **Private Networking**: All inter-node communication via private network (10.0.0.0/16)
- **Security**: Hetzner Firewall with minimal WAN exposure
- **Load Balancing**: Hetzner LB for API access with health checks
- **Automated Setup**: Cloud-init scripts for RKE2 installation and joining
- **Dynamic Scaling**: Easily adjust control plane and worker counts via variables

## Architecture

```
                    Internet
                       │
           ┌───────────┴───────────┐
           │  Hetzner Load Balancer│ (Port 6443)
           │    (Public IP)        │
           └───────────┬───────────┘
                       │
              ┌────────┴────────┐
              │  Private Network│ (10.0.0.0/16)
              │   (Internal)    │
              └────────┬────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
   ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
   │  CP-1   │   │  CP-2   │   │  CP-3   │  Control Plane
   │(Master) │   │(Master) │   │(Master) │  (etcd, API)
   └────┬────┘   └────┬────┘   └────┬────┘
        │              │              │
        └──────────────┼──────────────┘
                       │
              ┌────────┴────────┐
              │  Worker Nodes   │
              │  ┌───┬───┬───┐  │
              │  │W-1│W-2│W-3│  │
              │  └───┴───┴───┘  │
              └─────────────────┘
```

## Prerequisites

1. **Terraform** >= 1.0
2. **Hetzner Cloud Account** with API token
3. **SSH Key Pair** for server access
4. **Your Public IP** for SSH access restriction

## Quick Start

### 1. Configure

```bash
# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit the configuration with your settings
nano terraform.tfvars
```

### 2. Required Configuration in `terraform.tfvars`

```hcl
hcloud_token   = "your-hetzner-cloud-api-token"
ssh_public_key = "ssh-ed25519 AAA... your@email.com"
allowed_ssh_cidr = ["YOUR_IP/32"]  # Get your IP: curl -s https://ipinfo.io/ip
```

### 3. Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Access the Cluster

After deployment completes (wait 3-5 minutes for RKE2 installation):

```bash
# Retrieve kubeconfig (get the first control plane IP from output)
scp -i ~/.ssh/id_ed25519 root@<FIRST_CP_IP>:/etc/rancher/rke2/rke2.yaml ./kubeconfig.yaml

# Update kubeconfig to use load balancer IP
sed -i 's/127.0.0.1/<LOAD_BALANCER_IP>/g' kubeconfig.yaml

# Export and test
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes
```

## Network Security

### Firewall Rules

| Direction | Protocol | Port | Source | Description |
|-----------|----------|------|--------|-------------|
| Inbound | TCP | 22 | Your IP only | SSH access |
| Inbound | TCP | 6443 | Any | Kubernetes API (via LB) |
| Inbound | TCP | 9345 | Private Network | RKE2 supervisor |
| Inbound | TCP | 2379-2380 | Private Network | etcd peer-to-peer |
| Inbound | All | All | Private Network | Internal cluster traffic |
| Inbound | ICMP | - | Any | Ping |

**IMPORTANT**: Always restrict SSH to your IP (`allowed_ssh_cidr`) for security.

## Customization

### Scaling Nodes

```hcl
# terraform.tfvars
control_plane_count = 5  # Increase from 3 to 5
worker_count        = 5  # Increase from 2 to 5
```

### Using Different Server Types

```hcl
# terraform.tfvars
control_plane_server_type = "cpx31"  # More CPU/RAM for control plane
worker_server_type        = "cpx41"  # Larger workers for heavy workloads
```

### Changing CNI Plugin

```hcl
# terraform.tfvars
rke2_cni = "cilium"  # Options: cilium, canal, calico, flannel
```

## File Structure

```
.
├── versions.tf                    # Terraform and provider versions
├── providers.tf                   # Provider configuration
├── variables.tf                   # All configurable variables
├── network.tf                     # Private network and subnets
├── firewall.tf                    # Hetzner Cloud Firewall rules
├── servers.tf                     # Control plane and worker servers
├── loadbalancer.tf                # Hetzner Load Balancer
├── outputs.tf                     # Output values
├── cloud-init-control-plane.yaml  # Cloud-init for control plane
├── cloud-init-worker.yaml         # Cloud-init for workers
├── terraform.tfvars               # Your configuration (gitignored)
├── terraform.tfvars.example       # Example configuration
└── README.md                      # This file
```

## Important Notes

1. **Wait for Installation**: RKE2 installation takes 3-5 minutes after server creation
2. **Etcd Quorum**: Always use odd numbers for control plane (1, 3, 5, 7)
3. **Backup**: Enable backups for production control plane nodes (enabled by default)
4. **SSH Access**: Restrict to your IP only for security
5. **Load Balancer**: All API traffic goes through the LB, keeping nodes private

## Troubleshooting

### Check RKE2 Status

```bash
ssh root@<SERVER_IP> "systemctl status rke2-server"
ssh root@<WORKER_IP> "systemctl status rke2-agent"
```

### View Logs

```bash
# Control plane
ssh root@<SERVER_IP> "journalctl -u rke2-server -f"

# Worker
ssh root@<WORKER_IP> "journalctl -u rke2-agent -f"
```

### Common Issues

1. **Nodes not joining**: Check firewall rules and network connectivity
2. **etcd errors**: Ensure odd number of control plane nodes
3. **CNI issues**: Verify CNI plugin compatibility

## Cleanup

```bash
# Destroy all resources
terraform destroy
```

## License

MIT
