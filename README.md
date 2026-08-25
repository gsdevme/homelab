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
