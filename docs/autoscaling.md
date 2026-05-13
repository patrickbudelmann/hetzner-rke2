# Hetzner Cluster Autoscaler Guide

This guide covers configuring and operating the Kubernetes Cluster Autoscaler for Hetzner Cloud.

## Enable Autoscaler

Set the following variable in your Terraform configuration:

```hcl
enable_cluster_autoscaler = true
```

## Node Pool Configuration

Configure node pools using the `node_pools` variable. Each pool follows this format:

```
min:max:instanceType:region:name
```

### Example Configuration

```hcl
node_pools = [
  "1:5:cpx21:nbg1:worker-pool-nbg1",
  "2:10:cpx31:fsn1:worker-pool-fsn1"
]
```

This creates:
- Pool 1: 1-5 nodes, cpx21 instances, nbg1 region
- Pool 2: 2-10 nodes, cpx31 instances, fsn1 region

## Terraform State Drift Warning

**Important:** The autoscaler creates and destroys nodes dynamically, outside of Terraform's control.

- Terraform will detect drift when running `terraform plan`
- This is **expected behavior** - do not run `terraform apply` to "fix" autoscaler-created nodes
- Only manage the pool configuration (min/max/instance type) via Terraform
- Individual node lifecycle is managed by the autoscaler

## Verification

### Check Autoscaler is Running

```bash
kubectl get pods -n kube-system -l app=cluster-autoscaler
```

Expected output:
```
NAME                                    READY   STATUS    RESTARTS   AGE
cluster-autoscaler-xxxxx-xxxxx          1/1     Running   0          5m
```

### Check Scaling Activity

View autoscaler logs to see scaling decisions:

```bash
kubectl logs -n kube-system -l app=cluster-autoscaler --follow
```

Look for messages like:
- `Scale up: Adding group` - scaling up
- `Scale down: Removing node` - scaling down
- `Pod triggered scale up` - which pod caused scaling

### Check Node Pool Status

```bash
kubectl get nodes -l node-pool
```

## Troubleshooting

### Autoscaler Not Scaling Up

1. Check if nodes are pending due to quota limits in Hetzner Cloud
2. Verify the autoscaler has correct cloud credentials
3. Check logs for "no node group config" errors

### Autoscaler Not Scaling Down

1. Nodes may have pods preventing eviction (check pod disruption budgets)
2. Scale-down delay is configured (default: 10 minutes)
3. Check logs for "node is unremovable" messages
