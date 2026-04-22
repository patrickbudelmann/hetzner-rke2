# Quick Reference

## File Locations

| File | Purpose |
|------|---------|
| `docs/README.md` | Documentation index |
| `docs/architecture.md` | System architecture |
| `docs/security.md` | Security settings |
| `docs/deployment-guide.md` | Step-by-step deploy |
| `docs/cloud-init.md` | Automated configuration |
| `docs/network.md` | Network architecture |
| `docs/troubleshooting.md` | Common issues |
| `docs/examples.md` | Config examples |

## Essential Commands

```bash
# Initialize
terraform init

# Plan & Deploy
terraform plan
terraform apply

# Access Cluster
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes

# Get kubeconfig
scp -i ~/.ssh/id_ed25519 root@<CP_IP>:/etc/rancher/rke2/rke2.yaml ./kubeconfig.yaml
sed -i '' 's/127.0.0.1/<DNS_OR_LB_IP>/g' kubeconfig.yaml

# Useful Outputs
terraform output kubernetes_api_endpoint
terraform output cluster_summary
terraform output get_kubeconfig_command

# SSH
ssh -i ~/.ssh/id_ed25519 root@<CP_IP>

# Check Logs
journalctl -u rke2-server -f        # CP node
journalctl -u rke2-agent -f         # Worker
cat /var/log/cloud-init-output.log   # Cloud-init

# Destroy
terraform destroy
```
