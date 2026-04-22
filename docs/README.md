# RKE2 on Hetzner Cloud - Documentation

Welcome to the comprehensive documentation for deploying RKE2 Kubernetes clusters on Hetzner Cloud using Terraform.

## Table of Contents

1. **[Architecture Overview](architecture.md)** (190 lines) - How the cluster is structured
2. **[Security Guide](security.md)** (328 lines) - Token management, firewall rules, hardening
3. **[Deployment Guide](deployment-guide.md)** (319 lines) - Step-by-step deployment instructions
4. **[Cloud-Init Deep Dive](cloud-init.md)** (309 lines) - How automated configuration works
5. **[Network Architecture](network.md)** (382 lines) - Private network, subnets, load balancing
6. **[Troubleshooting](troubleshooting.md)** (474 lines) - Common issues and solutions
7. **[Examples](examples.md)** (510 lines) - Dev, staging, and production configurations
8. **[Quick Reference](quick-reference.md)** - Essential commands and reminders

## Quick Links

- [Main README](../README.md) - Project overview
- [QUICKSTART](../QUICKSTART.md) - 10-minute deployment guide
- [OPTIMIZATION_SUMMARY](../OPTIMIZATION_SUMMARY.md) - Technical optimization notes

## Project Status

- **Terraform**: >= 1.0
- **Provider**: hetznercloud/hcloud ~> 1.45
- **RKE2 Version**: v1.29.3+rke2r1 (configurable)
- **Architecture**: Security-first, SSH-provisioner-free

## Getting Started

New to this project? Start here:

1. Read the [Architecture Overview](architecture.md) to understand the system
2. Follow the [Security Guide](security.md) to set up tokens properly
3. Use the [Deployment Guide](deployment-guide.md) for your first cluster
4. Check [Examples](examples.md) for specific configurations

## Support

- RKE2 Docs: https://docs.rke2.io/
- Hetzner Docs: https://docs.hetzner.com/
- Hetzner CLI: https://github.com/hetznercloud/cli
