# Network Architecture

## Overview

All cluster communication happens over a private network (10.0.0.0/16), with only the Load Balancer and SSH ports exposed to the internet.

## Network Diagram

```
Internet
    │
    ├─ SSH (22/tcp) ────────────────────► [Firewall] ───► [CP/Worker Nodes]
    │                                      (Your IP only)
    │
    └─ Kubernetes API (6443/tcp) ────────► [Load Balancer]
                                              │
                                              │ (Private Network)
                                              ▼
                                    ┌─────────────────────┐
                                    │  Private Network    │
                                    │   10.0.0.0/16       │
                                    │  Zone: eu-central   │
                                    └─────────────────────┘
                                              │
                   ┌──────────────────────────┼──────────────────────────┐
                   │                          │                          │
           ┌───────▼────────┐       ┌────────▼────────┐       ┌────────▼────────┐
           │ Control Plane  │       │  Control Plane  │       │  Control Plane  │
           │   Subnet       │       │    Subnet       │       │    Subnet       │
           │  10.0.1.0/24   │       │   10.0.1.0/24   │       │   10.0.1.0/24   │
           │                │       │                 │       │                 │
           │   CP-1         │◄─────►│    CP-2         │◄─────►│    CP-3         │
           │ 10.0.1.10      │ etcd  │  10.0.1.11      │ etcd  │  10.0.1.12      │
           │ (Master)       │       │  (Master)       │       │  (Master)       │
           └───────┬────────┘       └────────┬────────┘       └────────┬────────┘
                   │                         │                         │
                   └─────────────────────────┼─────────────────────────┘
                                             │
                              ┌──────────────┼──────────────┐
                              │              │              │
                      ┌───────▼───┐  ┌──────▼────┐  ┌──────▼────┐
                      │  Worker   │  │  Worker   │  │  Worker   │
                      │  Subnet   │  │  Subnet   │  │  Subnet   │
                      │ 10.0.2.0/24│ │ 10.0.2.0/24│ │ 10.0.2.0/24│
                      │           │  │           │  │           │
                      │  W-1      │  │   W-2     │  │   W-3     │
                      │ 10.0.2.10 │  │  10.0.2.11│  │  10.0.2.12│
                      └───────────┘  └───────────┘  └───────────┘
                                             │
                   ┌─────────────────────────┘
                   │
           ┌───────▼────────┐
           │  Load Balancer │
           │    Subnet      │
           │  10.0.3.0/24   │
           │                │
           │   LB           │
           │ 10.0.3.10      │
           └────────────────┘
```

## Subnet Allocation

| Subnet | Purpose | Range | Default IPs |
|--------|---------|-------|-------------|
| 10.0.0.0/16 | Network CIDR | 65,534 hosts | - |
| 10.0.1.0/24 | Control Plane | 254 hosts | CP-1: 10.0.1.10, CP-2: 10.0.1.11... |
| 10.0.2.0/24 | Workers | 254 hosts | W-1: 10.0.2.10, W-2: 10.0.2.11... |
| 10.0.3.0/24 | Load Balancer | 254 hosts | LB: 10.0.3.10 |
| 10.42.0.0/16 | Pod CIDR | 65,534 pods | Managed by CNI |
| 10.43.0.0/16 | Service CIDR | 65,534 services | Managed by Kubernetes |

## IP Address Assignment

### Control Plane Nodes

```
CP-1: 10.0.1.10
CP-2: 10.0.1.11
CP-3: 10.0.1.12
CP-4: 10.0.1.13
CP-5: 10.0.1.14
...
CP-N: 10.0.1.(N + 9)
```

### Worker Nodes

```
W-1: 10.0.2.10
W-2: 10.0.2.11
W-3: 10.0.2.12
...
W-N: 10.0.2.(N + 9)
```

### Load Balancer

```
LB: 10.0.3.10 (fixed)
```

## Traffic Flows

### 1. kubectl → Kubernetes API

```
Your Machine ──► LB Public IP:6443 ──► LB Private IP:6443 ──► CP Node:6443
```

Route:
1. kubectl sends request to LB public IP on port 6443
2. LB forwards to one of the CP nodes on port 6443 (round robin)
3. CP node's kube-apiserver handles the request
4. Response goes back the same way

### 2. etcd Peer-to-Peer

```
CP-1 (2379-2380) ◄────► CP-2 (2379-2380)
     ▲                      ▲
     └──────────────────────┘
              CP-3 (2379-2380)
```

Route:
1. etcd on CP-1 connects to etcd on CP-2 using private IP
2. All communication stays within 10.0.1.0/24 subnet
3. Firewall allows port 2379-2380 only from private network

### 3. Worker → API Server (Registration)

```
Worker ──► First CP IP:9345 ──► RKE2 Supervisor
```

Route:
1. Worker agent connects to first CP node's private IP on port 9345
2. RKE2 supervisor authenticates using cluster token
3. Worker joins the cluster

### 4. Pod-to-Pod Communication

```
Pod A (10.42.0.5) ──► CNI (VXLAN 8472) ──► Pod B (10.42.0.8)
```

Route:
1. CNI (Cilium/Canal) creates overlay network
2. Pod IPs are allocated from 10.42.0.0/16
3. VXLAN encapsulation on UDP port 8472
4. Communication between nodes via private network

### 5. Service Communication

```
Pod A ──► Service ClusterIP (10.43.x.x) ──► kube-proxy ──► Pod B
```

Route:
1. Service IPs allocated from 10.43.0.0/16
2. kube-proxy handles NAT/load balancing
3. Actual traffic goes pod-to-pod via CNI

### 6. External Traffic Ingress

```
Internet User ──► Hetzner LB (80/443) ──► Service NodePort ──► Pod
```

Route:
1. User connects to LoadBalancer Service
2. HCCM (Hetzner Cloud Controller Manager) provisions Hetzner LB
3. LB forwards to node running pod
4. kube-proxy routes to correct pod

## Firewall Rules

### Control Plane Firewall

```
┌─────────────────────────────────────────────────────────────┐
│ INBOUND                                                     │
├──────────┬─────────┬───────────────────┬────────────────────┤
│ Protocol │ Port    │ Source            │ Purpose            │
├──────────┼─────────┼───────────────────┼────────────────────┤
│ TCP      │ 22      │ YOUR_IP/32        │ SSH                │
│ ICMP     │ -       │ 0.0.0.0/0         │ Ping               │
│ TCP      │ 6443    │ 0.0.0.0/0         │ Kubernetes API     │
│ TCP      │ 9345    │ 10.0.0.0/16       │ RKE2 Supervisor    │
│ TCP      │ 2379-80 │ 10.0.0.0/16       │ etcd               │
│ TCP      │ 10250   │ 10.0.0.0/16       │ Kubelet            │
│ TCP      │ 10257   │ 10.0.0.0/16       │ Controller Manager │
│ TCP      │ 10259   │ 10.0.0.0/16       │ Scheduler          │
│ UDP      │ 8472    │ 10.0.0.0/16       │ VXLAN              │
│ UDP      │ 51820-1 │ 10.0.0.0/16       │ WireGuard          │
│ TCP      │ all     │ 10.0.0.0/16       │ Internal TCP       │
│ UDP      │ all     │ 10.0.0.0/16       │ Internal UDP       │
└──────────┴─────────┴───────────────────┴────────────────────┘
```

### Worker Firewall

```
┌─────────────────────────────────────────────────────────────┐
│ INBOUND                                                     │
├──────────┬─────────┬───────────────────┬────────────────────┤
│ Protocol │ Port    │ Source            │ Purpose            │
├──────────┼─────────┼───────────────────┼────────────────────┤
│ TCP      │ 22      │ YOUR_IP/32        │ SSH                │
│ ICMP     │ -       │ 0.0.0.0/0         │ Ping               │
│ TCP      │ 30000+  │ Configurable      │ NodePort Services  │
│ UDP      │ 8472    │ 10.0.0.0/16       │ VXLAN              │
│ UDP      │ 51820-1 │ 10.0.0.0/16       │ WireGuard          │
│ TCP      │ all     │ 10.0.0.0/16       │ Internal TCP       │
│ UDP      │ all     │ 10.0.0.0/16       │ Internal UDP       │
└──────────┴─────────┴───────────────────┴────────────────────┘
```

## Load Balancer Configuration

### Services

| Listen Port | Target Port | Protocol | Health Check | Purpose |
|-------------|-------------|----------|--------------|---------|
| 6443 | 6443 | TCP | TCP:6443 | Kubernetes API |
| 9345 | 9345 | TCP | TCP:9345 | RKE2 Supervisor (optional) |

### Algorithm

- **Default**: `round_robin`
- **Alternative**: `least_connections`

### Health Checks

```
Protocol: TCP
Port: 6443 (API server)
Interval: 10 seconds
Timeout: 5 seconds
Retries: 3
```

## Network Zones

Hetzner Cloud Networks are tied to network zones:

| Zone | Locations | Example |
|------|-----------|---------|
| eu-central | nbg1, fsn1, hel1 | Germany |
| us-east | ash | Ashburn, VA |
| us-west | hil | Hillsboro, OR |
| ap-southeast | sin | Singapore |

**Important**: All resources in a network must be in the same zone but can be in different locations within that zone.

## DNS Considerations

### Internal DNS

Kubernetes provides internal DNS via CoreDNS:
- Service discovery: `<service>.<namespace>.svc.cluster.local`
- Pod DNS: `<pod-ip>.<namespace>.pod.cluster.local`

### External DNS

To expose services externally:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    load-balancer.hetzner.cloud/name: "my-lb"
spec:
  type: LoadBalancer
  ports:
  - port: 80
```

HCCM will:
1. Create a Hetzner Load Balancer
2. Assign a public IP
3. Configure health checks
4. Set up forwarding rules

## Customizing Network Configuration

### Change Network CIDR

```hcl
network_cidr         = "172.16.0.0/16"
control_plane_subnet = "172.16.1.0/24"
worker_subnet        = "172.16.2.0/24"
load_balancer_subnet = "172.16.3.0/24"
```

### Use Different Network Zone

```hcl
region       = "ash"
network_zone = "us-east"
```

### Custom Pod/Service CIDR

Edit `cloud-init-control-plane.yaml`:

```yaml
cluster-cidr: 192.168.0.0/16
service-cidr: 192.169.0.0/16
```

## Network Troubleshooting

### Check Connectivity Between Nodes

```bash
# From CP-1, ping CP-2
ping 10.0.1.11

# From CP-1, ping Worker
ping 10.0.2.10

# Check network interface
ip addr show ens10  # Hetzner private network interface
```

### Check Network Attachment

```bash
# On any node
ip route show

# Should show:
# 10.0.0.0/16 via 10.0.0.1 dev ens10
```

### Test Kubernetes DNS

```bash
# Run a test pod
kubectl run -it --rm debug --image=busybox:1.28 --restart=Never -- nslookup kubernetes.default
```

### Check CNI Status

```bash
# For Cilium
kubectl -n kube-system exec ds/cilium -- cilium status

# For Canal/Flannel
kubectl -n kube-system get pods -l app=flannel
```

### Network Performance Testing

```bash
# Install iperf3 on two nodes
apt-get install -y iperf3

# On node A (server)
iperf3 -s

# On node B (client)
iperf3 -c 10.0.1.10  # CP-1 IP
```

## Security Recommendations

1. **Never expose etcd** (2379-2380) to the internet
2. **Restrict SSH** to specific IPs only
3. **Use private network** for all internal traffic
4. **Enable CNI encryption** (WireGuard with Cilium)
5. **Monitor network policies** for pod-to-pod traffic

## See Also

- [Architecture](architecture.md) - Overall system architecture
- [Security](security.md) - Security best practices
- [Troubleshooting](troubleshooting.md) - Network troubleshooting
