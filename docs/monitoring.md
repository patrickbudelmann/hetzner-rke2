# Monitoring Stack Guide

This guide covers deploying and accessing the optional monitoring stack based on kube-prometheus-stack.

## Enable Monitoring

Set the following variable in your Terraform configuration:

```hcl
enable_monitoring = true
```

## Resource Requirements

The monitoring stack requires additional cluster resources:

| Component | CPU Request | Memory Request |
|-----------|-------------|----------------|
| Prometheus | 500m | 1Gi |
| Grafana | 100m | 256Mi |
| Alertmanager | 100m | 100Mi |
| Node Exporter (per node) | 100m | 50Mi |

**Minimum recommendation:** 2GB additional memory across the cluster.

## Access Grafana

### Port-Forward Method (Recommended for Initial Setup)

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Then open: http://localhost:3000

### Default Credentials

- **Username:** `admin`
- **Password:** `prom-operator`

**Important:** Change the default password after first login via Grafana UI (Configuration → Users).

## Access Prometheus

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Then open: http://localhost:9090

## Access Alertmanager

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

Then open: http://localhost:9093

## Exposing Grafana via Ingress (Future Step)

To expose Grafana publicly:

1. Configure ingress in your Terraform variables:
```hcl
grafana_ingress_enabled = true
grafana_ingress_host    = "grafana.your-domain.com"
```

2. Ensure you have:
   - TLS certificates configured
   - Authentication enabled (consider OAuth2 proxy or basic auth)
   - Network policies restricting access if needed

**Security Note:** Grafana provides powerful cluster insights. Always protect public endpoints with authentication.

## Verify Installation

```bash
# Check all monitoring components
kubectl get pods -n monitoring

# Expected: prometheus, grafana, alertmanager, node-exporter pods running
```

## Pre-configured Dashboards

The stack includes dashboards for:
- Kubernetes Cluster
- Kubernetes Compute Resources
- Node Exporter / USE Method
- Prometheus monitoring

Access via Grafana UI → Dashboards → Browse.
