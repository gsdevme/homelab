# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> This is a **public** repository. Never commit or document secrets, private IPs, internal hostnames, or domains.

## What this is

A Flux v2 GitOps monorepo for a personal Kubernetes homelab. Cluster state is declared in git and reconciled automatically — there is no manual `kubectl apply` in the normal workflow. Editing manifests here + committing to `master` is the deploy mechanism (Flux syncs roughly every 10m).

## Repository layout

- `clusters/<cluster>/` — one dir per cluster. Currently a single live cluster, `home`, which holds `flux-system/` (Flux controllers + GitRepository source) and Flux `Kustomization` CRDs: `infrastructure.yaml`, `apps.yaml`. These wire cluster → repo paths and set ordering via `dependsOn` (apps depend on infrastructure).
- `apps/` — application workloads. `base/` shared bases, `prod/` deployed apps, `no-deployment/` defined-but-inactive.
- `infrastructure/` — core services (cert-manager, nginx ingress, longhorn, etc.). `base/` + per-cluster overlays. `infrastructure/base/sources/` defines Flux `HelmRepository` CRDs (the chart repos everything pulls from).

## How deployment works (Flux DAG)

`clusters/<cluster>/*.yaml` are `kustomize.toolkit.fluxcd.io` `Kustomization` objects. Each points at a repo `path` and reconciles it with `prune: true`. Dependencies are explicit:

```
infrastructure  →  apps
```

So a change to a shared source or infra component can gate app reconciliation. Any cluster-scoped differences are handled by per-cluster overlay dirs, not branches.

## App structure

Each app is a Kustomize dir = one namespace. Three styles, often mixed in one dir:

- **Helm**: a `release.yaml` (`HelmRelease`, `helm.toolkit.fluxcd.io/v2beta1`) referencing a `HelmRepository` from `infrastructure/base/sources/`, with the chart **version pinned**. Values come from a `values.yaml` fed in via a Kustomize `configMapGenerator` (see `apps/prod/tesla/`).
- **Native**: plain `Deployment`/`Service`/`Ingress` manifests.
- **Hybrid**: e.g. Postgres via Helm + custom app Deployments.

### Adding / changing an app

1. Work in `apps/prod/<app>/` (or the relevant cluster overlay).
2. Provide `namespace.yaml` + workload manifests and/or `release.yaml`.
3. List everything in `kustomization.yaml` (set `namespace:`; use `configMapGenerator` for Helm values).
4. Ensure the parent cluster `apps.yaml` path already covers the dir (usually `./apps/prod`).
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
