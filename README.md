# Homelab Monorepo

A [Flux v2](https://fluxcd.io/) GitOps monorepo for a personal Kubernetes homelab.
Cluster state is declared here and reconciled automatically — there is no manual
`kubectl apply` in the normal workflow. **Editing manifests and committing to
`master` is the deploy mechanism**; Flux syncs roughly every 10 minutes.

One live cluster, `home`: a k3s cluster of four nodes — an amd64 control-plane and
three arm64 Raspberry Pis. Workloads that must land on a Pi use `arm64` node affinity
or a nodeSelector.

## Layout

| Path | What it holds |
|---|---|
| `clusters/home/` | The Flux entrypoint — controllers, the `GitRepository` source, and the `Kustomization` CRDs that wire cluster to repo paths. |
| `apps/` | Application workloads. `prod/` is deployed; `base/` and `no-deployment/` are not. |
| `infrastructure/` | Core services — cert-manager, nginx ingress, letsencrypt, the 1Password operator, the k3s upgrade controller. |
| `infrastructure/base/sources/` | Flux `HelmRepository` CRDs — the chart repos everything else pulls from. |

## How it deploys

`clusters/home/` defines two Flux `Kustomization`s, both with `prune: true`, ordered
by an explicit `dependsOn`:

```
infrastructure  →  apps
```

Each points at exactly one path — `./infrastructure/prod` and `./apps/prod` — and
those two roots behave differently, which is the main thing to know before adding
anything:

- **`apps/prod/` has no root `kustomization.yaml`.** Flux recurses every subdirectory,
  so creating a directory there is enough to make an app live.
- **`infrastructure/base/kustomization.yaml` is an explicit allow-list.** A component
  only deploys if it is listed there. This is why `longhorn` exists in the tree but is
  not running — it is commented out.

Because infrastructure gates apps, a broken shared source or infra component will
hold up app reconciliation too.

Everything outside those two roots is inert: `apps/base/`, `apps/no-deployment/`,
`infrastructure/raspberry-pi-cluster/`, and any base component missing from the
allow-list.

## Adding an app

Each app directory is one namespace, and mixes three styles as needed: a Helm
`HelmRelease` with the chart version pinned and values supplied through a
`configMapGenerator`; plain `Deployment`/`Service`/`Ingress` manifests; or both.

1. Create `apps/prod/<app>/` with a `namespace.yaml` and your manifests.
2. List everything in a `kustomization.yaml` and set `namespace:`.
3. Commit. Flux does the rest.

For infrastructure, add the component to `infrastructure/base/kustomization.yaml` as
well — otherwise it deploys nothing.

### Conventions

- Ingress: `kubernetes.io/ingress.class: nginx`, with
  `cert-manager.io/cluster-issuer: letsencrypt-prod` for TLS.
- Pin Helm chart versions; declare the chart repo in `infrastructure/base/sources/`.
- Set resource requests and limits, and `revisionHistoryLimit: 2`.
- Never commit secrets — see below.

There is no repo-wide build or test. Sanity-check a directory with
`kustomize build <dir>` before committing; real validation happens in-cluster.

## Secrets (1Password operator)

Cluster secrets live in a dedicated `homelab` 1Password vault. The
[1Password Kubernetes operator](infrastructure/base/onepassword/) turns an
`OnePasswordItem` custom resource into a normal Kubernetes `Secret`, so no
plaintext secret is ever committed here.

`OnePasswordItem` resources are safe to commit — they contain only a path
(vault and item name), never a value:

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: example
  namespace: default
spec:
  itemPath: "vaults/homelab/items/example"
```

The operator only watches namespaces listed in `operator.watchNamespace` in
[`release.yaml`](infrastructure/base/onepassword/release.yaml). Add a namespace
there before adding an `OnePasswordItem` to it. That list must stay non-empty:
emptying it escalates the operator from per-namespace access to read/write on
every secret in the cluster.

### The token expires every 90 days

The operator authenticates with a 1Password service account token, held in the
`onepassword-service-account-token` Secret. It is created out of band and is
deliberately not in git.

**90 days is 1Password's maximum**, and expiry can only be set when the service
account is created — there is no way to extend an existing one. So rotating means
creating a *new* service account and revoking the old one, roughly quarterly.

Nothing in the cluster will warn you before it lapses.

#### What actually breaks when it expires

Verified against a dead token, not assumed:

| | |
|---|---|
| Existing `Secret`s | **Unaffected.** They stay in etcd with their current values. |
| Pods consuming them | **Unaffected.** Mounts and env vars keep working. |
| Updates made in 1Password | **Stop propagating** to already-synced Secrets. |
| New `OnePasswordItem`s | **No Secret is created.** |
| The operator pod | **CrashLoopBackOff.** It validates the token at startup and exits. |

So the cluster keeps running and nothing goes down — but secrets silently stop
tracking 1Password. Expect to notice it as "why didn't that secret update", long
after the fact.

One accidental safeguard: because the operator fails at startup, a rolling update
with a bad token never becomes ready, so the previous healthy pod is left running.
The breakage only becomes total once that pod is replaced for some other reason.

Recovery needs nothing beyond a working token — the operator catches up on its own,
applying any updates and creating any Secrets that were blocked while it was down.

#### Rotating

```bash
# 1. New service account. Name it for the month so the old one is unambiguous.
TOK=$(op service-account create homelab-k8s-<yyyy-mm> --expires-in=90d \
        --vault "homelab:read_items" --raw)

# 2. Store it FIRST - the token is shown exactly once.
op item edit homelab-k8s --vault Personal "credential[password]=$TOK"

# 3. Update the cluster. The operator reads the token at startup, hence the restart.
kubectl -n onepassword create secret generic onepassword-service-account-token \
  --from-literal=token="$TOK" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n onepassword rollout restart deploy/onepassword-connect-operator
```

Then revoke the previous service account at 1password.com under Developer Tools —
there is no CLI for this, and service accounts are not listable from the CLI.

Verify a rotation end to end rather than trusting a `Running` pod. Point a throwaway
`OnePasswordItem` at a throwaway vault item, check the resulting Secret's value, then
delete both.

Keep the token in a vault the service account itself cannot read, and never set
`operator.serviceAccountToken.value` in `release.yaml` — that renders the literal
token into the manifest, and this repo is public.

### Rebuilding the cluster

The operator cannot supply its own token, so exactly one secret is created by hand.
Do this *before* Flux reconciles, or the operator crash-loops on the missing Secret:

```bash
kubectl create namespace onepassword
kubectl -n onepassword create secret generic onepassword-service-account-token \
  --from-literal=token="$(op read 'op://Personal/homelab-k8s/credential')"
```

Everything else follows from Flux.
