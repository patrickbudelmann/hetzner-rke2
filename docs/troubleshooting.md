# Troubleshooting Guide

## Quick Diagnostics

```bash
# Check all nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# Check node logs
kubectl describe node <node-name>

# SSH to node and check RKE2
ssh root@<NODE_IP> "systemctl status rke2-server"
```

## Common Issues

### 1. TLS Certificate Error

**Error:**
```
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

**Causes:**
- Kubeconfig points to Load Balancer IP but cert doesn't include it yet
- Cloud-init LB discovery script hasn't completed
- Manual cert update needed

**Solutions:**

**Option A: Wait (Recommended)**
```bash
# Wait 2-3 more minutes for cloud-init to complete
cat /var/log/rke2-tls-discovery.log
# Look for: "SUCCESS: RKE2 restarted with new TLS certificate"
```

**Option B: Use CP Node IP**
```bash
# Get first CP IP
CP_IP=$(terraform output -json control_plane_nodes | jq -r '.[0].public_ipv4')

# Update kubeconfig
sed -i '' "s/127.0.0.1/$CP_IP/g" kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes
```

**Option C: Manual Fix**
```bash
# SSH to first CP
ssh root@<CP_IP>

# Edit config
nano /etc/rancher/rke2/config.yaml

# Add LB IP to tls-san:
tls-san:
  - 10.0.1.10
  - 10.0.3.10
  - <LB_PUBLIC_IP>

# Restart RKE2
systemctl restart rke2-server
```

### 2. Nodes Not Joining Cluster

**Error:**
```
Unable to connect to the server: connection refused
```

**Causes:**
- First CP node not ready yet
- Firewall blocking port 9345
- Token mismatch
- Network connectivity issues

**Solutions:**

**Check CP node is ready:**
```bash
ssh root@<FIRST_CP_IP> "systemctl status rke2-server"
```

**Check firewall rules:**
```bash
# Check what ports are open
ss -tlnp | grep -E "6443|9345|2379|2380"
```

**Verify token:**
```bash
# On first CP
cat /var/lib/rancher/rke2/server/token

# On worker node
cat /etc/rancher/rke2/config.yaml | grep token
```

**Check logs:**
```bash
# On worker
journalctl -u rke2-agent -n 50

# On CP
journalctl -u rke2-server -n 50 | grep -i "connection\|error\|failed"
```

### 3. etcd Quorum Lost

**Error:**
```
etcdserver: not capable
```

**Causes:**
- Even number of CP nodes (etcd needs odd number for quorum)
- CP nodes cannot reach each other
- Certificate issues between etcd peers

**Solutions:**

**Check CP count is odd:**
```bash
terraform output control_plane_count
# Must be: 1, 3, 5, or 7
```

**Check etcd health:**
```bash
# On any CP node
/var/lib/rancher/rke2/bin/kubectl exec -it -n kube-system etcd-<node-name> -- etcdctl endpoint health

# Check etcd logs
journalctl -u rke2-server | grep -i etcd
```

**Force quorum (last resort):**
```bash
# Stop RKE2 on failed node
systemctl stop rke2-server

# On a healthy CP node, remove failed member
/var/lib/rancher/rke2/bin/kubectl exec -it -n kube-system etcd-<healthy-node> -- etcdctl member list
/var/lib/rancher/rke2/bin/kubectl exec -it -n kube-system etcd-<healthy-node> -- etcdctl member remove <failed-member-id>
```

### 4. HCCM Not Running

**Error:**
```
Failed to create cloud provider: hcloud: unable to authenticate
```

**Causes:**
- HCCM secret has wrong token
- Network ID mismatch
- HCCM pod not scheduled on CP node

**Solutions:**

**Check secret:**
```bash
kubectl get secret hcloud -n kube-system -o yaml
# Verify token value
```

**Check HCCM logs:**
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=hcloud-cloud-controller-manager
```

**Check network ID:**
```bash
# Get network ID from Hetzner
hcloud network list

# Verify in Terraform state
terraform show | grep network_id
```

**Restart HCCM:**
```bash
kubectl delete pod -n kube-system -l app.kubernetes.io/name=hcloud-cloud-controller-manager
```

### 5. CSI Volume Pending

**Error:**
```
pvc-xxx-xxx is Pending
```

**Causes:**
- CSI driver not running
- No node available in correct zone
- Volume quota exceeded

**Solutions:**

**Check CSI pods:**
```bash
kubectl get pods -n kube-system | grep hcloud-csi
```

**Check events:**
```bash
kubectl describe pvc <pvc-name>
```

**Check storage class:**
```bash
kubectl get storageclass
kubectl get pvc
```

**Verify Hetzner quota:**
```bash
# Check in Hetzner Console
# Project → Costs → Overview
```

### 6. Cloud-Init Failed

**Error:**
```
Cloud-init status: error
```

**Solutions:**

**Check cloud-init logs:**
```bash
# On affected node
cat /var/log/cloud-init-output.log | tail -50
cat /var/log/cloud-init.log | grep -i error
```

**Check if RKE2 installed:**
```bash
which rke2
rke2 --version
systemctl status rke2-server
```

**Re-run cloud-init (if needed):**
```bash
cloud-init clean --logs
cloud-init init
cloud-init modules
```

### 7. Token Not Wiped

**Error:**
```
/etc/rancher/rke2/.hcloud-token still exists after deployment
```

**Solutions:**

**Manual wipe:**
```bash
ssh root@<CP_IP> "rm -f /etc/rancher/rke2/.hcloud-token && sync"
```

**Check discovery script:**
```bash
ssh root@<CP_IP> "cat /var/log/rke2-tls-discovery.log"
```

**Common causes:**
- Script crashed before reaching wipe step
- Script didn't have permission to delete file
- Disk issue prevented deletion

### 8. Load Balancer Health Check Failing

**Error:**
```
Load balancer shows health check failures
```

**Solutions:**

**Check RKE2 API is responding:**
```bash
# On CP node
curl -k https://localhost:6443/healthz

# Should return: ok
```

**Check firewall rules:**
```bash
# Ensure port 6443 is open
curl -k https://<CP_IP>:6443/healthz
```

**Check LB targets:**
```bash
# Using hcloud CLI
hcloud load-balancer describe <LB_NAME>
```

**Restart LB service targets:**
```bash
# In Hetzner Console or via API
# Detach and re-attach targets
```

### 9. kubectl Connection Refused

**Error:**
```
The connection to the server <IP>:6443 was refused
```

**Causes:**
- RKE2 not running
- Wrong IP in kubeconfig
- Firewall blocking

**Solutions:**

**Check if RKE2 is running:**
```bash
ssh root@<CP_IP> "systemctl is-active rke2-server"
ssh root@<CP_IP> "curl -k https://localhost:6443/healthz"
```

**Verify kubeconfig:**
```bash
cat kubeconfig.yaml | grep server
# Should point to correct IP
```

**Check if API port is open:**
```bash
ssh root@<CP_IP> "ss -tlnp | grep 6443"
```

### 10. Terraform Apply Fails

**Error:**
```
Error: Invalid function argument
```

**Solutions:**

**Validate terraform:**
```bash
terraform validate
terraform fmt
```

**Check variable values:**
```bash
# Ensure all required variables are set
grep -E "hcloud_token|ssh_public_key" terraform.tfvars
```

**Check for syntax errors:**
```bash
terraform plan -input=false
```

**Common fixes:**
- Missing closing brace in terraform.tfvars
- Invalid CIDR notation in network settings
- Invalid region name
- Odd number for control_plane_count

## Getting Help

### Collect Diagnostic Information

```bash
# Save node information to file
kubectl get nodes -o yaml > nodes.yaml
kubectl get pods -n kube-system -o yaml > system-pods.yaml
kubectl get events -n kube-system > system-events.txt

# On CP node
journalctl -u rke2-server > rke2-logs.txt
cat /var/log/rke2-tls-discovery.log > tls-discovery.txt
cat /etc/rancher/rke2/config.yaml > rke2-config.txt
```

### Check Terraform State

```bash
# List resources
terraform state list

# Show specific resource
terraform state show hcloud_server.control_plane[0]

# Check for drift
terraform plan -detailed-exitcode
```

### Useful Commands

```bash
# Check all hcloud resources
hcloud server list
hcloud network list
hcloud load-balancer list
hcloud firewall list

# Check resource details
hcloud server describe <SERVER_NAME>
hcloud load-balancer describe <LB_NAME>
```

## Recovery Procedures

### Recover from Failed CP Node

```bash
# On remaining healthy CP nodes
systemctl stop rke2-server

# Backup etcd
rsync -av /var/lib/rancher/rke2/server/db/ /backup/etcd/

# Remove failed node from etcd
/var/lib/rancher/rke2/bin/kubectl exec -n kube-system etcd-<healthy-node> -- etcdctl member list
/var/lib/rancher/rke2/bin/kubectl exec -n kube-system etcd-<healthy-node> -- etcdctl member remove <failed-id>

# Restart healthy nodes
systemctl start rke2-server
```

### Complete Cluster Rebuild

```bash
# Destroy everything
terraform destroy

# Clean up local state
rm -f kubeconfig.yaml terraform.tfstate terraform.tfstate.backup

# Verify Hetzner resources are gone
hcloud server list
hcloud network list

# Re-deploy
terraform apply
```

### Restore from etcd Backup

```bash
# Stop RKE2
systemctl stop rke2-server

# Remove current etcd data
rm -rf /var/lib/rancher/rke2/server/db/

# Restore backup
rsync -av /backup/etcd/ /var/lib/rancher/rke2/server/db/

# Start RKE2
systemctl start rke2-server
```
