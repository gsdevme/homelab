# Proxmox

OpenTofu for the Proxmox host: the guests that live outside the Kubernetes
cluster. Nothing here is deployed by Flux and nothing here depends on the
cluster being up. It is applied by hand, from a laptop.

For now it manages LXC containers only. The pipeline was proven end to end
with two throwaway containers that have since been removed; `containers.tf`
declares none until something real is needed.

| Path | What it holds |
|---|---|
| `containers.tf` | Every container on the host, one `module` block (or `for_each` entry) each. |
| `templates.tf` | Container templates, downloaded by the node itself. |
| `variables.tf` | Facts about the host: node name, datastores, bridge. |
| `modules/lxc/` | One unprivileged container with an SSH key for root. |
| `.env.op` | 1Password references for the endpoint, API token and SSH public key. |
| `backend.hcl.example` | Where the state file goes; copy to `backend.hcl`. |

## Secrets

No secret is in git, in a tfvars file or in the state.

- The provider reads `PROXMOX_VE_ENDPOINT` and `PROXMOX_VE_API_TOKEN` from the
  environment. `.env.op` holds 1Password references for them, and
  `op run --env-file=.env.op -- tofu ...` resolves the references for that one
  process. They are never written to disk.
- The SSH **public** key arrives the same way, as `TF_VAR_ssh_public_key`, read
  from an SSH key item in 1Password. It is not a secret, but it stays out of a
  public repo.
- Containers have no root password: log in with the key through the 1Password
  SSH agent, or with `pct enter <vmid>` on the host.
- State and `*.tfvars` are gitignored all the same, because later guests will
  put secrets in the state. A variable that carries a secret must be
  `sensitive = true` and come from `.env.op`.

## One-off setup

### 1. An API token on the Proxmox host

As root on the node. The role is the least that creating containers and
downloading and deleting templates needs (`Datastore.Allocate` is what deleting
a template takes); a `403` from `tofu apply` names any privilege that turns out
to be missing.

```bash
pveum role add OpenTofu -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit SDN.Use Sys.Audit Sys.Modify VM.Allocate VM.Audit VM.Config.CPU VM.Config.Disk VM.Config.Memory VM.Config.Network VM.Config.Options VM.PowerMgmt"
```

```bash
pveum user add opentofu@pve
```

```bash
pveum aclmod / -user opentofu@pve -role OpenTofu
```

```bash
pveum user token add opentofu@pve tofu --privsep 0
```

The last command prints the token secret once. The value the provider wants is
the token ID and the secret joined with `=`: `opentofu@pve!tofu=<secret>`.

### 2. 1Password: a vault, an SSH key and the token

Everything lives in a vault named `proxmox`, separate from `homelab`: the
cluster's 1Password service account reads `homelab`, and a token that can
create guests on the host is more than the cluster should hold.

```bash
op vault create proxmox
```

An SSH key item named `proxmox-guest-root`. 1Password generates it, so the
private key never touches a disk; its public key is what `.env.op` reads.

```bash
op item create --category "SSH Key" --title proxmox-guest-root --vault proxmox --ssh-generate-key ed25519
```

An API Credential item named `proxmox-opentofu` with two fields:

| Field | Value |
|---|---|
| `endpoint` | The API URL, `https://<host>:8006/`. |
| `api-token` | `opentofu@pve!tofu=<secret>` from step 1. |

```bash
op item create --category "API Credential" --title proxmox-opentofu --vault proxmox 'endpoint[text]=https://<host>:8006/' 'api-token[concealed]='
```

Then paste the token into `api-token` in the 1Password app, so the secret
stays out of the shell history.

To log in to the guests, turn on the SSH agent in the 1Password app
(Settings → Developer → Use the SSH agent) and point `ssh` at it:

```
# ~/.ssh/config
Host *
    IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

### 3. The state file

State is a local file on the laptop. Keep it outside the checkout so
`git clean -x` cannot delete it:

```bash
cp backend.hcl.example backend.hcl
```

Edit the `path` in `backend.hcl`, then:

```bash
tofu init -backend-config=backend.hcl
```

The first `init` writes `.terraform.lock.hcl`, which pins the provider's
checksums. Commit it.

To move the state later (to a NAS share, say), change `path` and run
`tofu init -migrate-state -backend-config=backend.hcl`.

### 4. Check the host facts

`variables.tf` describes the host: node `venus`, guest disks on `local-lvm`,
templates on `local`, bridge `vmbr0`, and a self-signed API certificate. Change
the defaults there when the host changes.

The template URL goes stale when Proxmox publishes a new build. If the download
fails, list what is current on the node with `pveam available --section system`
and update `debian_lxc_template_url`.

## Plan and apply

```bash
op run --env-file=.env.op -- tofu plan
```

```bash
op run --env-file=.env.op -- tofu apply
```

`tofu output` prints each container's VM ID and DHCP address. Then, with the
1Password SSH agent configured:

```bash
ssh root@<address>
```

## Adding a container

Add a `module` block to `containers.tf`. Only the first six arguments are
required; `modules/lxc/variables.tf` lists the rest (cores, memory, disk size,
static address, VLAN).

```hcl
module "example" {
  source = "./modules/lxc"

  hostname = "example"
  vm_id    = 120

  node_name        = var.node_name
  datastore_id     = var.guest_datastore
  bridge           = var.bridge
  template_file_id = proxmox_download_file.debian_lxc.id
  ssh_public_keys  = [trimspace(var.ssh_public_key)]
}
```

The template and the keys are only read when a container is built. Changing
either affects containers created afterwards and leaves existing ones alone.

## Removing a container

Delete its `module` block (and output) and apply. The container is destroyed
and its disk purged; the template on the node is kept.

## If the state is lost

Nothing is lost on the host. Start a fresh state and import each container by
node and VM ID:

```bash
op run --env-file=.env.op -- tofu import 'module.example.proxmox_virtual_environment_container.this' venus/120
```
