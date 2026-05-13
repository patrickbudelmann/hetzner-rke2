# Quick Start Guide - RKE2 on Hetzner Cloud

## 🚀 Get Up and Running in 10 Minutes

### Step 1: Configure (2 minutes)

```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your settings
nano terraform.tfvars
```

**Required changes in `terraform.tfvars`:**

```hcl
# 1. Set your Hetzner API token
hcloud_token = "your-token-here"

# 2. Set your SSH public key
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID... your@email.com"

# 3. RESTRICT SSH TO YOUR IP (CRITICAL!)
# Get your IP: curl -s https://ipinfo.io/ip
allowed_ssh_cidr = ["YOUR.IP.ADDRESS.HERE/32"]
```

### Step 2: Deploy (5-7 minutes)

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy everything
terraform apply
```

**Expected output:**
- 3 control plane nodes
- 2 worker nodes
- 1 load balancer
- Private network with subnets
- Firewalls with security rules

### Step 3: Access Your Cluster (2 minutes)

```bash
# Get the first control plane IP
CP_IP=$(terraform output -raw first_control_plane_ip)
LB_IP=$(terraform output -raw load_balancer_public_ipv4)

# Copy kubeconfig
scp -i ~/.ssh/id_ed25519 root@$CP_IP:/etc/rancher/rke2/rke2.yaml ./kubeconfig.yaml

# Update to use load balancer
sed -i "s/127.0.0.1/$LB_IP/g" kubeconfig.yaml

# Set KUBECONFIG
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Verify cluster
kubectl get nodes -o wide
```

**Expected output:**
```
NAME               STATUS   ROLES                       AGE   VERSION
rke2-cp-1          Ready    control-plane,etcd,master   5m    v1.29.3+rke2r1
rke2-cp-2          Ready    control-plane,etcd,master   4m    v1.29.3+rke2r1
rke2-cp-3          Ready    control-plane,etcd,master   3m    v1.29.3+rke2r1
rke2-worker-1      Ready    worker                      2m    v1.29.3+rke2r1
rke2-worker-2      Ready    worker                      2m    v1.29.3+rke2r1
```

### Step 4: Verify Components (1 minute)

```bash
# Check HCCM (Cloud Controller)
kubectl get pods -n kube-system -l app.kubernetes.io/name=hcloud-cloud-controller-manager

# Check CSI Driver
kubectl get pods -n kube-system -l app=hcloud-csi

# Check Storage Classes
kubectl get storageclass

# Check NGINX Ingress Controller (if enabled)
kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Check cert-manager (if enabled)
kubectl get pods -n cert-manager -l app.kubernetes.io/name=cert-manager
```

### Step 5: SSH to Workers (Jump Host Pattern)

Worker nodes have no public IPs for security. Use a control plane node as a jump host:

```bash
# Get IPs
CP_IP=$(terraform output -raw first_control_plane_ip)
WORKER1_PRIVATE_IP="10.0.2.10"  # Check with: kubectl get nodes -o wide

# SSH via jump host
ssh -J root@$CP_IP root@$WORKER1_PRIVATE_IP

# Or add to ~/.ssh/config for convenience:
cat >> ~/.ssh/config <<EOF
Host rke2-cp-*
  User root
  IdentityFile ~/.ssh/id_ed25519
  ProxyJump $CP_IP
EOF
```

### Step 6: Test Ingress (Optional)

Create a test ingress to verify the NGINX Ingress Controller:

```bash
# Create a test deployment
kubectl create deployment nginx --image=nginx --port=80

# Expose it
kubectl expose deployment nginx --port=80

# Create an ingress resource
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: test.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
EOF

# Get the ingress load balancer IP
kubectl get ingress test-ingress

# Add to /etc/hosts for testing:
# <INGRESS_LB_IP> test.example.com
# curl http://test.example.com
```

### Step 7: Test Storage (Optional)

```bash
# Create a test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: hcloud-volumes
EOF

# Verify PVC is bound
kubectl get pvc test-pvc
```

---

## ✅ Pre-Deployment Checklist

- [ ] Hetzner Cloud account created
- [ ] Hetzner API token generated (read/write permissions)
- [ ] SSH key pair generated (`ssh-keygen -t ed25519`)
- [ ] Terraform installed (>= 1.0)
- [ ] `terraform.tfvars` created and configured
- [ ] `allowed_ssh_cidr` set to YOUR IP address
- [ ] Reviewed server types and costs
- [ ] Chosen region (fsn1, nbg1, hel1, etc.)

---

## 🔧 Common Commands

### Terraform Management

```bash
# View outputs
terraform output

# View specific output
terraform output kubernetes_api_endpoint

# Show current state
terraform show

# Refresh state
terraform refresh

# Destroy everything (CAREFUL!)
terraform destroy
```

### Cluster Management

```bash
# SSH to control plane
ssh -i ~/.ssh/id_ed25519 root@$(terraform output -raw first_control_plane_ip)

# Check RKE2 status on control plane
systemctl status rke2-server

# Check RKE2 status on workers
systemctl status rke2-agent

# View logs
journalctl -u rke2-server -f

# Get cluster token (sensitive)
terraform output -raw rke2_token
```

### kubectl Operations

```bash
# Set kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Get nodes
kubectl get nodes -o wide

# Get all pods
kubectl get pods -A

# Get system pods
kubectl get pods -n kube-system

# Check node details
kubectl describe node <node-name>
```

---

## 🐛 Troubleshooting

### Issue: Nodes not joining

```bash
# Check logs on worker
ssh root@<worker-ip> "journalctl -u rke2-agent -n 100"

# Verify token
terraform output -raw rke2_token

# Check firewall rules
hcloud firewall describe <firewall-id>
```

### Issue: Can't access API

```bash
# Check load balancer
hcloud load-balancer describe <lb-id>

# Verify kubeconfig
kubectl config view

# Check if LB is healthy
curl -k https://<lb-ip>:6443/healthz
```

### Issue: HCCM not working

```bash
# Check HCCM logs
kubectl logs -n kube-system -l app.kubernetes.io/name=hcloud-cloud-controller-manager

# Verify secret exists
kubectl get secret hcloud -n kube-system
```

---

## 💰 Cost Estimation

| Component | Type | Monthly Cost |
|-----------|------|-------------|
| Control Plane | cpx21 × 3 | ~€30 |
| Workers | cpx31 × 2 | ~€40 |
| Load Balancer | lb11 | ~€5 |
| Volumes (optional) | 100GB × 2 | ~€8 |
| **Total** | | **~€75-85/month** |

*Prices as of 2026, check Hetzner website for current pricing*

---

## 📚 Next Steps

1. **Deploy your applications!**

2. **Configure DNS for Ingress**:
   - Get the ingress load balancer IP: `kubectl get svc -n ingress-nginx`
   - Create DNS A records pointing to this IP for your domains

3. **Set up cert-manager ClusterIssuer** for automatic TLS:
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-prod
   spec:
     acme:
       server: https://acme-v02.api.letsencrypt.org/directory
       email: your@email.com
       privateKeySecretRef:
         name: letsencrypt-prod
       solvers:
       - http01:
           ingress:
             ingressClassName: nginx
   EOF
   ```

4. **Enable Cluster Autoscaler** (optional):
   - Set `enable_cluster_autoscaler = true` in terraform.tfvars
   - Autoscaler will manage a separate node pool outside Terraform

---

## 🆘 Getting Help

- Check `.context` file for detailed project information
- Review `OPTIMIZATION_SUMMARY.md` for technical details
- See `README.md` for full documentation
- Consult RKE2 docs: https://docs.rke2.io/
- Hetzner docs: https://docs.hetzner.com/

---

**Happy Clustering! 🎉**
