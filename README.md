# Homelab Monorepo

```
apps
└── base
    └── smokeping
clusters
└── raspberry-pi-cluster
    ├── flux-system
    └── infrastructure.yaml
infrastructure
├── kustomization.yaml
├── longhorn
├── nginx
└── sources
    ├── influxdata.yaml
    ├── jetstack.yaml
    ├── kustomization.yaml
    ├── longhorn.yaml
    ├── nginx.yaml
    └── prometheus.yaml
```

## Common Problems

Disabling the default storage class used in k3s in favour of longhorn

```json
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```
