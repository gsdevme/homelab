# Prerequisites & Disaster Recovery

```
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --no-deploy traefik" sh

# Grab kubectl from /etc/rancher/k3s/k3s.yaml

# Bootstrap the cluster with gitops
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=homelab \
  --branch=master \
  --path="kubernetes-cluster/test" \
  --personal
```

## Services

### Home Assistant

#### Building the Image

Due to the deprecation of YAML a .storage bootstrap should create a single user/password but its
a brittle setup

```
cd services/home-assistant

make build version=0.117.1
```
