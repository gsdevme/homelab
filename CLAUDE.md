# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> This is a **public** repository. Never commit or document secrets, public hostnames, or domains. Internal RFC1918 IPs (e.g. the `172.16.x.x` addresses in `k3sup/home-cluster/install.sh`) are non-routable and fine to keep.

## What this is

A Flux v2 GitOps monorepo for a personal Kubernetes homelab. Cluster state is declared in git and reconciled automatically — there is no manual `kubectl apply` in the normal workflow. Editing manifests here + committing to `master` is the deploy mechanism (Flux syncs roughly every 10m).

## Repository layout

- `clusters/<cluster>/` — one dir per cluster. Currently a single live cluster, `home`, which holds `flux-system/` (Flux controllers + GitRepository source) and Flux `Kustomization` CRDs: `infrastructure.yaml`, `apps.yaml`. These wire cluster → repo paths and set ordering via `dependsOn` (apps depend on infrastructure).
- `apps/` — application workloads. `base/` shared bases, `prod/` deployed apps, `no-deployment/` defined-but-inactive.
- `infrastructure/` — core services (cert-manager, letsencrypt issuers, `traefik-public`/`traefik-private` ingress, 1Password operator, etc.). `base/` + per-cluster overlays. `infrastructure/base/sources/` defines Flux `HelmRepository` CRDs (the chart repos everything pulls from).
- `k3sup/home-cluster/install.sh` — one-off cluster bootstrap (k3s via k3sup). The actual `k3sup install`/`join` commands are **commented out**, so it's a historical record, not run on deploys. The server runs with `--disable traefik,servicelb`: k3s's bundled Traefik is off (the Traefik here is the Flux HelmRelease), and so is **servicelb** (Klipper) — there is no load-balancer controller, so a `LoadBalancer` Service stays Pending forever (ingress uses hostPorts instead) and nothing clears the `service.kubernetes.io/load-balancer-cleanup` finalizer (deleting a Service carrying it hangs in Terminating until the finalizer is removed by hand). **local-storage** (the default `local-path` StorageClass / `rancher.io/local-path` provisioner, which backs the app PVCs — e.g. tesla's) is **kept**. longhorn is defined but commented out of the infra allow-list, so it is not running.
- `proxmox/` — OpenTofu (`bpg/proxmox` provider, version pinned) for the Proxmox host: guests that live **outside** the cluster, LXC containers for now via `modules/lxc`. Flux never reads it; it is applied by hand from a laptop with `op run --env-file=.env.op -- tofu apply`. Secrets reach it only as environment variables from the 1Password references in `.env.op`; state is a local file whose path is set in the gitignored `backend.hcl`. `proxmox/README.md` has the setup.

> `README.md` is the human-facing overview of the same ground this file covers, plus the 1Password secrets workflow. It was rewritten in `524d29f`; the stale directory tree it used to carry is gone. Still trust the actual tree over any prose if they disagree.

## How deployment works (Flux DAG)

`clusters/<cluster>/*.yaml` are `kustomize.toolkit.fluxcd.io` `Kustomization` objects. Each points at a repo `path` and reconciles it with `prune: true`. Dependencies are explicit:

```
infrastructure  →  apps
```

So a change to a shared source or infra component can gate app reconciliation. Any cluster-scoped differences are handled by per-cluster overlay dirs, not branches.

The `home` cluster reconciles **exactly** `./apps/prod` and `./infrastructure/prod`, and the two roots work differently:

- `apps/prod/` has **no** root `kustomization.yaml` — Flux recurses every subdir, so dropping a new app dir under `apps/prod/` makes it live automatically.
- `infrastructure/prod/kustomization.yaml` composes `../base`, and `infrastructure/base/kustomization.yaml` is an **explicit allow-list** of components. A component only deploys if listed there (e.g. `longhorn` is currently commented out, so it is *not* running despite existing in the tree).

Everything outside those two roots is inert: `apps/base/`, `apps/no-deployment/`, `infrastructure/raspberry-pi-cluster/`, and any base component not listed in `infrastructure/base/kustomization.yaml` deploy nothing. `proxmox/` is not Kubernetes and is never reconciled.

## App structure

Each app is a Kustomize dir = one namespace. Three styles, often mixed in one dir:

- **Helm**: a `release.yaml` (`HelmRelease`, `helm.toolkit.fluxcd.io/v2`) referencing a `HelmRepository` from `infrastructure/base/sources/`, with the chart **version pinned**. Values come from a `values.yaml` fed in via a Kustomize `configMapGenerator` (see `apps/prod/tesla/`).
- **Native**: plain `Deployment`/`Service`/`Ingress` manifests.
- **Hybrid**: e.g. Postgres via Helm + custom app Deployments.

### Adding / changing an app

1. Work in `apps/prod/<app>/` (or the relevant cluster overlay).
2. Provide `namespace.yaml` + workload manifests and/or `release.yaml`.
3. List everything in `kustomization.yaml` (set `namespace:`; use `configMapGenerator` for Helm values).
4. For apps, creating the dir under `apps/prod/` is enough (Flux recurses it — no root list to edit). For infra, add the component to `infrastructure/base/kustomization.yaml`'s `resources:` or it won't deploy.
5. Match existing conventions (below). Commit — Flux deploys.

## Conventions

- Ingress: see the Ingress section below — always set `spec.ingressClassName`.
- Pin Helm chart versions in `release.yaml`; sources live in `infrastructure/base/sources/`.
- Workloads pinned to arm64 (Raspberry Pi) nodes use `arm64` node affinity / nodeSelector.
- Set resource requests/limits and `revisionHistoryLimit: 2`; HPAs use `autoscaling/v2` (K8s 1.26+).
- Keep `secrets.yaml`, `*env`, and kubeconfigs out of git (already gitignored).

## Ingress (traefik-public / traefik-private)

Two Flux-managed Traefik instances (`infrastructure/base/traefik-{public,private}/`, chart pinned in `release.yaml`), each a single-pod hostPort DaemonSet on 80/443 with **no Service**: `traefik-public` on kube-master (the only node the router forwards to — internet-facing), `traefik-private` on pi-alpha (LAN-only; its entrypoints also carry an RFC1918 `ipAllowList`). See README.md for the overview.

- Each instance watches **only** its own IngressClass (`traefik-public` / `traefik-private`); neither is default, so an Ingress without `spec.ingressClassName` is served by nothing.
- **Public app**: `ingressClassName: traefik-public` + `cert-manager.io/cluster-issuer: letsencrypt-prod` (HTTP-01, solver served by traefik-public).
- **Private app**: `ingressClassName: traefik-private` + `cert-manager.io/cluster-issuer: letsencrypt-prod-dns01` (Cloudflare DNS-01; token from the `cloudflare-api-token` OnePasswordItem in `cert-manager`, which is why the 1Password operator's `watchNamespace` includes `cert-manager`). The host also needs a LAN DNS override to pi-alpha's IP; LAN DNS is dnsmasq outside the cluster and the entry is added **manually** — nothing in this repo does it.
- traefik.io CRD objects (`Middleware`, `IngressRoute`, …) must carry `kubernetes.io/ingress.class: <instance class>`, or the instance ignores them (a router referencing an ignored middleware is dropped). Attach with `traefik.ingress.kubernetes.io/router.middlewares: <namespace>-<name>@kubernetescrd` (see `apps/prod/wealthfolio/`).
- HTTP→HTTPS redirect, compression and HSTS are applied at the entrypoint on both instances — don't add per-app middlewares for them.
- ExternalName backends (only traefik-public allows them, e.g. Home Assistant in `apps/prod/smart-home/`): Traefik dials the Service `port`, not `targetPort`, so `port` must equal the upstream's real port.
- traefik-public owns the traefik.io CRDs (`crds: Create`/`CreateReplace`); traefik-private `dependsOn` it and skips CRDs.

## Issues and pull requests

Multi-step work is tracked as GitHub issues: an epic with a task list of phase issues under one label; each phase has a "To do" checklist and a "Done when" paragraph. Work on a phase goes through a branch and a pull request, not a direct commit to `master`.

- When a pull request is opened or merged, run the `project-manager` agent (`.claude/agents/project-manager.md`) on it; a `PostToolUse` hook (`.claude/hooks/pull-request-issues.py`) asks for this after `gh pr create` and `gh pr merge`. It links the issues the pull request resolves (`Closes #N`) or moves on (`Part of #N`) in the description, and after a merge ticks what was finished.
- A merge is not a rollout. After merging, reconcile and verify in the cluster, then run the agent again with what was verified so it can tick the items that needed it.
- Opening, closing and rewording issues stays with the owner.
- The hook is stdlib Python; check it with `python3 -m unittest discover tests`.

## Local checks

There is no repo-wide build/test/lint. Validation happens in-cluster via Flux; use `kustomize build <dir>` locally to sanity-check a Kustomize dir before committing. For `proxmox/`, run `tofu fmt -check -recursive` and `tofu validate`; a merge there changes nothing until someone runs `tofu apply`.

## Commits

Angular Conventional Commits (`semantic-release`): `type(scope): description`, e.g. `feat(tesla): ...`, `fix(hpa): ...`, `build(postgresql): ...`. Scope is usually the app/component.
