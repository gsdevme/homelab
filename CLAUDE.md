# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> This is a **public** repository. Never commit or document secrets, public hostnames, or domains. Internal RFC1918 IPs (e.g. the `172.16.x.x` addresses in `k3sup/home-cluster/install.sh`) are non-routable and fine to keep.

## What this is

A Flux v2 GitOps monorepo for a personal Kubernetes homelab. Cluster state is declared in git and reconciled automatically — there is no manual `kubectl apply` in the normal workflow. Editing manifests here + committing to `master` is the deploy mechanism (Flux syncs roughly every 10m).

## Repository layout

- `clusters/<cluster>/` — one dir per cluster. Currently a single live cluster, `home`, which holds `flux-system/` (Flux controllers + GitRepository source) and Flux `Kustomization` CRDs: `infrastructure.yaml`, `apps.yaml`. These wire cluster → repo paths and set ordering via `dependsOn` (apps depend on infrastructure).
- `apps/` — application workloads. `base/` shared bases, `prod/` deployed apps, `no-deployment/` defined-but-inactive.
- `infrastructure/` — core services (cert-manager, nginx ingress, longhorn, etc.). `base/` + per-cluster overlays. `infrastructure/base/sources/` defines Flux `HelmRepository` CRDs (the chart repos everything pulls from).
- `k3sup/home-cluster/install.sh` — one-off cluster bootstrap (k3s via k3sup). The actual `k3sup install`/`join` commands are **commented out**, so it's a historical record, not run on deploys. It disables only k3s's built-in `traefik` (nginx-ingress replaces it). k3s's **servicelb** (Klipper — `svclb-*` pods back the nginx `LoadBalancer` Service) and **local-storage** (the default `local-path` StorageClass / `rancher.io/local-path` provisioner, which backs the app PVCs — e.g. tesla's) are **kept**. longhorn is defined but commented out of the infra allow-list, so it is not running.

> `README.md` is stale — it describes an older multi-cluster layout (`clusters/prod`, `raspberry-pi-cluster`, drone sources, etc.) that no longer exists. Trust the actual tree and this file over it.

## How deployment works (Flux DAG)

`clusters/<cluster>/*.yaml` are `kustomize.toolkit.fluxcd.io` `Kustomization` objects. Each points at a repo `path` and reconciles it with `prune: true`. Dependencies are explicit:

```
infrastructure  →  apps
```

So a change to a shared source or infra component can gate app reconciliation. Any cluster-scoped differences are handled by per-cluster overlay dirs, not branches.

The `home` cluster reconciles **exactly** `./apps/prod` and `./infrastructure/prod`, and the two roots work differently:

- `apps/prod/` has **no** root `kustomization.yaml` — Flux recurses every subdir, so dropping a new app dir under `apps/prod/` makes it live automatically.
- `infrastructure/prod/kustomization.yaml` composes `../base`, and `infrastructure/base/kustomization.yaml` is an **explicit allow-list** of components. A component only deploys if listed there (e.g. `longhorn` is currently commented out, so it is *not* running despite existing in the tree).

Everything outside those two roots is inert: `apps/base/`, `apps/no-deployment/`, `infrastructure/raspberry-pi-cluster/`, and any base component not listed in `infrastructure/base/kustomization.yaml` deploy nothing.

## App structure

Each app is a Kustomize dir = one namespace. Three styles, often mixed in one dir:

- **Helm**: a `release.yaml` (`HelmRelease`, `helm.toolkit.fluxcd.io/v2beta1`) referencing a `HelmRepository` from `infrastructure/base/sources/`, with the chart **version pinned**. Values come from a `values.yaml` fed in via a Kustomize `configMapGenerator` (see `apps/prod/tesla/`).
- **Native**: plain `Deployment`/`Service`/`Ingress` manifests.
- **Hybrid**: e.g. Postgres via Helm + custom app Deployments.

### Adding / changing an app

1. Work in `apps/prod/<app>/` (or the relevant cluster overlay).
2. Provide `namespace.yaml` + workload manifests and/or `release.yaml`.
3. List everything in `kustomization.yaml` (set `namespace:`; use `configMapGenerator` for Helm values).
4. For apps, creating the dir under `apps/prod/` is enough (Flux recurses it — no root list to edit). For infra, add the component to `infrastructure/base/kustomization.yaml`'s `resources:` or it won't deploy.
5. Match existing conventions (below). Commit — Flux deploys.

## Conventions

- Ingress: `kubernetes.io/ingress.class: nginx` + `cert-manager.io/cluster-issuer: letsencrypt-prod` for TLS.
- Pin Helm chart versions in `release.yaml`; sources live in `infrastructure/base/sources/`.
- Workloads pinned to arm64 (Raspberry Pi) nodes use `arm64` node affinity / nodeSelector.
- Set resource requests/limits and `revisionHistoryLimit: 2`; HPAs use `autoscaling/v2` (K8s 1.26+).
- Keep `secrets.yaml`, `*env`, and kubeconfigs out of git (already gitignored).

## Local checks

There is no repo-wide build/test/lint. Validation happens in-cluster via Flux; use `kustomize build <dir>` locally to sanity-check a Kustomize dir before committing.

## Commits

Angular Conventional Commits (`semantic-release`): `type(scope): description`, e.g. `feat(tesla): ...`, `fix(hpa): ...`, `build(postgresql): ...`. Scope is usually the app/component.
