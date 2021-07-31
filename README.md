# Homelab Monorepo

```
apps
├── base
│   └── smokeping
│       ├── config.yaml
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       └── statefulset.yaml
└── raspberry-pi-cluster
    └── smokeping
        ├── ingress.yaml
        ├── kustomization.yaml
        └── statefulset.yaml
clusters
├── prod
│   ├── flux-system
│   └── infrastructure.yaml
└── raspberry-pi-cluster
    ├── apps.yaml
    ├── flux-system
    └── infrastructure.yaml
infrastructure
├── base
│   ├── cert-manager
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   └── release.yaml
│   ├── kubernetes-secret-generator
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   └── release.yaml
│   ├── kustomization.yaml
│   ├── longhorn
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   └── release.yaml
│   ├── nginx
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   └── release.yaml
│   └── sources
│       ├── influxdata.yaml
│       ├── jetstack.yaml
│       ├── kustomization.yaml
│       ├── longhorn.yaml
│       ├── mittwald.yaml
│       ├── nginx.yaml
│       └── prometheus.yaml
├── prod
│   ├── basic-auth.yaml
│   ├── kustomization.yaml
│   └── longhorn-ingress-value.yaml
└── raspberry-pi-cluster
    └── kustomization.yaml
```
