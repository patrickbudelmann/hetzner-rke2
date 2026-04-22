# Deployment Guide

## Prerequisites

Before deploying, ensure you have:

- **Terraform** >= 1.0 installed: `terraform version`
- **SSH key pair** generated: `ssh-keygen -t ed25519 -C "your-email@example.com"`
- **Hetzner Cloud account** with a project
- **API tokens** (see Security Guide for two-token strategy)
- **Your public IP address** (for firewall restriction)

## Step 1: Prepare Your Environment

### Get Your Public IP

```bash
# On macOS/Linux
curl -s https://ipinfo.io/ip
curl -s https://api.ipify.org

# On Windows (PowerShell)
(Invoke-WebRequest -uri "http://ifconfig.me/ip").Content
```

### Generate SSH Key (if needed)

```bash
# Generate a new SSH key pair
ssh-keygen -t ed25519 -C "your-email@example.com"

# Get the public key content
cat ~/.ssh/id_ed25519.pub
# Output: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID... your-email@example.com
```

### Create Hetzner API Token

1. Log in to [Hetzner Cloud Console](https://console.hetzner.cloud/)
2. Select your project
3. Navigate to **Security** → **API Tokens**
4. Create a token:
   - **Name**: `terraform-main`
   - **Permissions**: Read & Write
5. **SAVE THE TOKEN VALUE** - you can't see it again!

## Step 2: Configure terraform.tfvars

```bash
# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your settings
nano terraform.tfvars  # or vim, or your preferred editor
```

### Minimal Configuration (Required)

```hcl
# Required: Main Hetzner API token
hcloud_token = "your-main-token-here"

# Required: SSH public key
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID... your-email@example.com"

# CRITICAL: Restrict SSH to YOUR IP ONLY
allowed_ssh_cidr = ["YOUR.PUBLIC.IP.ADDRESS/32"]
```

### DNS Configuration (Recommended)

```hcl
# DNS name for the Kubernetes API endpoint
# This name will be baked into the RKE2 TLS certificate
cluster_api_dns = "k8s.example.com"
```

**After deployment**, create a DNS A record:
```
k8s.example.com  →  <LOAD_BALANCER_IP>
```

### Optional Configuration

```hcl
# Cluster settings
cluster_name = "production"
environment  = "prod"
region       = "fsn1"

# Node counts
control_plane_count = 3
worker_count        = 2

# Server types
cp_server_type = "cpx21"
worker_type    = "cpx31"

# RKE2 version
rke2_version = "v1.29.3+rke2r1"
rke2_cni     = "cilium"

# Security
enable_hccm       = true
enable_csi_driver = true
enable_backups    = true
```

## Step 3: Initialize Terraform

```bash
terraform init
```

This downloads the Hetzner Cloud provider and sets up the working directory.

## Step 4: Review the Plan

```bash
terraform plan
```

Carefully review the output. You should see:
- Number of servers being created
- Network and subnet configuration
- Firewall rules
- Load balancer
- Expected costs

## Step 5: Deploy

```bash
terraform apply
```

Type `yes` when prompted.

### Deployment Timeline

```
0:00  - Terraform starts creating resources
1:00  - Network and subnets created
2:00  - SSH key created
3:00  - First control plane node created (RKE2 starts installing)
4:00  - Additional CP nodes joining
5:00  - Worker nodes joining
6:00  - Load balancer created
8:00  - RKE2 fully started on all nodes
10:00 - Cluster fully ready
```

Total time: **10-15 minutes**

## Step 6: Configure kubectl

After deployment completes, configure kubectl to access your cluster.

### Get the kubeconfig

```bash
# Get first CP node IP
CP_IP=$(terraform output -json control_plane_nodes | jq -r '.[0].public_ipv4')

# Copy kubeconfig from first CP node
scp -i ~/.ssh/id_ed25519 root@$CP_IP:/etc/rancher/rke2/rke2.yaml ./kubeconfig.yaml

# Or use the output command
terraform output -raw get_kubeconfig_command
```

### Update kubeconfig server address

**If you configured `cluster_api_dns`:**
```bash
# Update kubeconfig to use DNS name (macOS)
sed -i '' "s/127.0.0.1/${var.cluster_api_dns}/g" kubeconfig.yaml

# Update kubeconfig to use DNS name (Linux)
sed -i "s/127.0.0.1/${var.cluster_api_dns}/g" kubeconfig.yaml
```

**If you did NOT configure `cluster_api_dns`:**
```bash
# Get LB IP
LB_IP=$(terraform output -raw load_balancer_public_ipv4)

# Update kubeconfig to use LB IP (macOS)
sed -i '' "s/127.0.0.1/$LB_IP/g" kubeconfig.yaml

# Update kubeconfig to use LB IP (Linux)
sed -i "s/127.0.0.1/$LB_IP/g" kubeconfig.yaml
```

### Set KUBECONFIG and test

```bash
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Verify cluster
kubectl get nodes -o wide

# Expected output:
NAME              STATUS   ROLES                       AGE   VERSION
production-cp-1   Ready    control-plane,etcd,master   5m    v1.29.3+rke2r1
production-cp-2   Ready    control-plane,etcd,master   4m    v1.29.3+rke2r1
production-cp-3   Ready    control-plane,etcd,master   3m    v1.29.3+rke2r1
production-w-1    Ready    worker                      2m    v1.29.3+rke2r1
production-w-2    Ready    worker                      2m    v1.29.3+rke2r1
```

## Step 7: Verify Components

### Check HCCM (Cloud Controller Manager)

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=hcloud-cloud-controller-manager

# Expected: 1 pod running
```

### Check CSI Driver

```bash
kubectl get pods -n kube-system -l app=hcloud-csi

# Expected: Controller + node pods running
kubectl get storageclass

# Expected: hcloud-volumes, hcloud-volumes-encrypted
```

### Check All System Pods

```bash
kubectl get pods -n kube-system
```

## Step 8: Deploy Applications

Your cluster is ready! Deploy your applications:

```bash
# Example: Deploy nginx
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Check service (HCCM will create a Hetzner LB automatically)
kubectl get service nginx
```

## Post-Deployment Commands

### Useful Terraform Outputs

```bash
# Show all outputs
terraform output

# Specific outputs
terraform output kubernetes_api_endpoint
terraform output rke2_version
terraform output cluster_summary
terraform output ssh_control_plane_commands
```

### SSH Access

```bash
# SSH to first CP node
ssh -i ~/.ssh/id_ed25519 root@<CP_IP>

# Check RKE2 status
systemctl status rke2-server

# View logs
journalctl -u rke2-server -f

# Check cloud-init logs
cat /var/log/cloud-init-output.log
```

## Scaling the Cluster

### Add Worker Nodes

```hcl
# terraform.tfvars
worker_count = 5  # Change from 2 to 5
```

```bash
terraform apply
```

### Add Control Plane Nodes

```hcl
# terraform.tfvars
control_plane_count = 5  # Change from 3 to 5 (odd number!)
```

```bash
terraform apply
```

**Note**: RKE2 will automatically add new nodes to the etcd cluster.

## Destroying the Cluster

```bash
# Destroy everything (BE CAREFUL!)
terraform destroy

# Or target specific resources
terraform destroy -target hcloud_server.workers
```

**Warning**: Destroying will delete all servers, load balancers, volumes, and networks. Make sure to back up any data first!

## Next Steps

- Read [Examples](examples.md) for specific configurations
- Check [Troubleshooting](troubleshooting.md) if you encounter issues
- Review [Network Architecture](network.md) for network details
- See [Cloud-Init Deep Dive](cloud-init.md) to understand automation
