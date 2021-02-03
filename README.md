# Homelab Monorepo

[![Build Status](https://travis-ci.com/gsdevme/homelab.svg?branch=master)](https://travis-ci.com/gsdevme/homelab)

# Prerequisites & Disaster Recovery


```
# Install K3s (turn off SELinx, Firewalld etc on the host)
# install on other hosts if multi node cluster
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --no-deploy traefik" sh

# WITH MYSQL
#curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --no-deploy traefik --datastore-endpoint=mysql://username:password@tcp(127.0.0.1:3306)/kubernetes" sh

# Grab kubectl from /etc/rancher/k3s/k3s.yaml and install Flux
brew install flux

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
