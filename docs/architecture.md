# Architecture Overview

## High-Level Architecture

```
                        Internet
                           │
              ┌────────────┴────────────┐
              │   Hetzner Load Balancer  │  (Public IPv4)
              │     Port 6443 (TCP)      │
              └────────────┬────────────┘
                           │
                  ┌────────┴────────┐
                  │  Private Network │   10.0.0.0/16 (eu-central)
                  │   (Internal)     │
                  └────────┬────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
   ┌─────▼─────┐    ┌─────▼─────┐    ┌─────▼─────┐
   │   CP-1    │    │   CP-2    │    │   CP-3    │   Control Plane
   │ 10.0.1.10 │    │ 10.0.1.11 │    │ 10.0.1.12 │   (etcd + API)
   │ (Master)  │    │ (Master)  │    │ (Master)  │
   └─────┬─────┘    └─────┬─────┘    └─────┬─────┘
         │                │                │
         └────────────────┼────────────────┘
                          │
                 ┌────────┴────────┐
                 │  Worker Nodes    │
                 │  10.0.2.0/24     │
                 │ ┌───┬───┬───┐   │
                 │ │W-1│W-2│W-3│   │
                 │ └───┴───┴───┘   │
                 └──────────────────┘
```

## Component Breakdown

### Control Plane Nodes

- **Count**: Odd numbers only (1, 3, 5, 7) for etcd quorum
- **Default Type**: `cpx21` (2 vCPU, 4GB RAM, 40GB NVMe)
- **Role**: Runs etcd, kube-apiserver, kube-scheduler, kube-controller-manager
- **Network**: Private IP from `10.0.1.0/24` subnet
- **Access**: SSH (restricted), Kubernetes API (via LB)

### Worker Nodes

- **Count**: Configurable (default: 2)
- **Default Type**: `cpx31` (4 vCPU, 8GB RAM, 80GB NVMe)
- **Role**: Runs user workloads
- **Network**: Private IP from `10.0.2.0/24` subnet

### Load Balancer

- **Type**: `lb11` (configurable)
- **Ports**: 
  - 6443/tcp - Kubernetes API
  - 9345/tcp - RKE2 Supervisor (optional)
- **Targets**: All control plane nodes (via private network)
- **Algorithm**: Round robin (configurable)

### Private Network

- **CIDR**: `10.0.0.0/16`
- **Zone**: `eu-central`
- **Subnets**:
  - Control Plane: `10.0.1.0/24`
  - Workers: `10.0.2.0/24`
  - Load Balancer: `10.0.3.0/24`

## Deployment Flow

```
Phase 1: Terraform Provisioning (5-7 minutes)
├── Create Network and Subnets
├── Create SSH Key
├── Create Control Plane Nodes
│   └── Cloud-init starts RKE2 installation
├── Create Worker Nodes
│   └── Cloud-init starts RKE2 agent installation
└── Create Load Balancer (after nodes exist)
    └── Attach to network, configure targets

Phase 2: Cloud-Init Execution (10-15 minutes per node)
First CP Node:
├── Install packages (curl, jq, qemu-guest-agent)
├── Install RKE2 server
├── Start RKE2 (cluster-init mode)
├── Wait for RKE2 ready (kubeconfig exists, API responsive)
├── Background: Start LB discovery script
│   ├── Poll Hetzner API (30 retries, 20s delay)
│   ├── Extract LB public IPv4
│   ├── Update RKE2 config TLS-SAN
│   ├── Restart RKE2 to regenerate certificate
│   └── WIPE Hetzner token from disk
└── Label node with Hetzner metadata

Other CP Nodes:
├── Install RKE2 server
├── Start RKE2 (join mode, connect to first CP)
├── Wait for RKE2 ready
├── Background: Start LB discovery script (same logic)
└── Label node

Worker Nodes:
├── Install RKE2 agent
├── Start RKE2 agent (connect to first CP)
└── Label node

Phase 3: Post-Deployment (Manual)
├── Revoke temporary Hetzner token (CRITICAL!)
├── Retrieve kubeconfig
├── Update kubeconfig with LB IP
└── Deploy applications
```

## Data Flow

### Kubernetes API Access
```
kubectl → Load Balancer (6443) → CP Node (6443) → kube-apiserver
```

### etcd Communication
```
CP-1 (2379-2380) ↔ CP-2 (2379-2380) ↔ CP-3 (2379-2380)
```

### Node Registration
```
Worker → RKE2 Supervisor (9345) → CP-1 (9345)
```

### Internal Pod Communication
```
Pod A (10.42.0.x) ↔ CNI (VXLAN 8472) ↔ Pod B (10.42.0.y)
```

## Resource Dependencies

```
network → subnets → ssh_key → control_plane → workers → load_balancer
  ↑_______________________________________________________↑
  (control_plane needs network, LB needs control_plane as targets)
```

## Key Design Decisions

### Why Cloud-Init Instead of SSH Provisioners?

**Traditional approach**:
```
Terraform → SSH → Run commands remotely
Problem: Requires unencrypted SSH keys, complex error handling
```

**Our approach**:
```
Terraform → Cloud-init user_data → Server self-configures
Benefit: No SSH access needed during deployment, encrypted keys work
```

### Why Temporary Token Pattern?

- Hetzner API tokens are all-powerful (no read-only scopes)
- We need to query the API from inside servers (for LB discovery)
- Temporary token is created separately, used once, then revoked
- Limits exposure window to ~10 minutes (deployment time)

### Why No SSH During Deployment?

- Encrypted SSH keys can't be used by Terraform provisioners
- Cloud-init is more robust (runs on first boot, idempotent)
- Simpler architecture (no connection blocks, no key management)
- Better security posture (ssh only for maintenance)

## Files and Their Roles

| File | Purpose | Created By | Managed By |
|------|---------|------------|------------|
| `versions.tf` | Terraform and provider versions | Terraform | Static |
| `variables.tf` | All configuration options | Human | terraform.tfvars |
| `network.tf` | Private network and subnets | Terraform | Terraform |
| `firewall.tf` | Security rules | Terraform | Terraform |
| `servers.tf` | Server definitions | Terraform | Terraform |
| `loadbalancer.tf` | LB configuration | Terraform | Terraform |
| `cloud-init-control-plane.yaml` | CP server bootstrap script | Human | Cloud-init |
| `cloud-init-worker.yaml` | Worker bootstrap script | Human | Cloud-init |
| `terraform.tfvars` | Your configuration | Human | Human |
