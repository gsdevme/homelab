# Proxmox

OpenTofu for the Proxmox host: the guests that live outside the Kubernetes
cluster. Nothing here is deployed by Flux and nothing here depends on the
cluster being up. It is applied by hand, from a laptop.

It manages LXC containers and virtual machines. Each pipeline was proven end
to end with two throwaway guests that have since been removed (containers, then
VMs 9101 and 9102); `containers.tf` and `vms.tf` declare none until something
real is needed.

| Path | What it holds |
|---|---|
| `containers.tf` | Every container on the host, one `module` block (or `for_each` entry) each. |
| `templates.tf` | Container templates, downloaded by the node itself. |
| `vms.tf` | Every virtual machine on the host, one `module` block (or `for_each` entry) each. |
| `images.tf` | VM images from this repo's releases, downloaded by the node itself. |
| `variables.tf` | Facts about the host: node name, datastores, bridge, and the image release VMs boot from. |
| `modules/lxc/` | One unprivileged container with an SSH key for root. |
| `modules/vm/` | One virtual machine from an image, with an SSH key for root. |
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
- Tofu never SSHes to the node or to the guests. For a VM, the image is the
  only way first-boot configuration arrives; Proxmox's own cloud-init adds the
  hostname, root key and network.
- State and `*.tfvars` are gitignored all the same, because later guests will
  put secrets in the state. A variable that carries a secret must be
  `sensitive = true` and come from `.env.op`.

## One-off setup

### 1. An API token on the Proxmox host

As root on the node. The role is the least that creating containers and VMs
and downloading and deleting templates and images needs (`Datastore.Allocate`
is what deleting a template takes; `VM.Config.CDROM`, `VM.Config.Cloudinit`
and `VM.Config.HWType` are what a VM adds); a `403` from `tofu apply` names any
privilege that turns out to be missing.

```bash
pveum role add OpenTofu -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit SDN.Use Sys.Audit Sys.Modify VM.Allocate VM.Audit VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.PowerMgmt"
```

To add privileges to an existing role, `pveum role modify OpenTofu -privs "..."`
with the full list.

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

VM images are downloaded to `local` as `import` content, which lets the node
import a qcow2 as a VM disk (Proxmox VE 8.4 and later). `local` does not carry
that content type by default; add it once, keeping the types it already has:

```bash
pvesm set local --content vztmpl,images,backup,iso,import
```

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

`tofu output` prints each guest's VM ID and DHCP address. Then, with the
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

## Virtual machines

Add a `module` block to `vms.tf`. Only the first seven arguments are required;
`modules/vm/variables.tf` lists the rest. The defaults are 1 core, 2048 MB of
memory, a 16 GB disk and DHCP; a static address, VLAN and tags are optional.

```hcl
module "example" {
  source = "./modules/vm"

  hostname = "example"
  vm_id    = 130

  node_name       = var.node_name
  datastore_id    = var.guest_datastore
  bridge          = var.bridge
  image_file_id   = proxmox_download_file.debian_vm.id
  ssh_public_keys = [trimspace(var.ssh_public_key)]
}
```

Use `proxmox_download_file.alpine_vm.id` for Alpine instead of Debian.

Proxmox's native cloud-init sets the hostname, the root key and the network.
There are no snippets: nothing is written to the node and nothing SSHes to it.
Everything else is already in the image (see Images below).

The address comes from the QEMU guest agent, so it appears once the VM has
booted and the agent is up. Add an output for the module, as `outputs.tf`
shows, and `tofu output` prints it:

```bash
op run --env-file=.env.op -- tofu output
```

On first boot, Proxmox's own cloud-init default (`upgrade`) also runs a package
upgrade, alongside the image's `homelab-firstboot`. Only `root@pam` can change
that setting, so it is left on.

### Bumping the image

Change `images_release` in `variables.tf` to a newer tag from the repo's
releases and apply. The node downloads the new images beside the old ones.
Only VMs created afterwards use them: like the LXC module, `modules/vm`
ignores changes to the image and the keys on an existing VM, so nothing is
replaced. The release `images_release` pins is never pruned.

### Removing a VM

Delete its `module` block (and output) and apply. The VM is destroyed and its
disks purged; the images on the node are kept.

## Images

The VM images are built by this repo: `images/` holds the build, and
`.github/workflows/images.yml` runs it. Nothing there is deployed by Flux.

The workflow runs weekly (Mondays 03:17 UTC), on a manual run from the Actions
tab, and on any push that changes `images/**` or the workflow. Each run
publishes a GitHub Release of this repo with three assets: the Debian 13 and
Alpine 3.23 qcow2 images and `SHA256SUMS`.

| Built from | Tag | Kind |
|---|---|---|
| `master` | `images-YYYYMMDD` | Release |
| Any other branch | `images-YYYYMMDD-<7-char commit>` | Pre-release |

After publishing, it keeps the last 8 releases and the last 2 pre-releases and
deletes older ones, except the tag `images_release` pins, which is never
deleted.

GitHub pauses scheduled workflows after 60 days without commits. If a weekly
release stops appearing, re-enable the workflow under Actions.

### What the images contain

Both start from the upstream cloud image, fully upgraded on the build day, and
add:

- The QEMU guest agent, enabled.
- Podman, rootful, with the Docker-compatible socket, the `podman-docker` shim
  (so `docker ...` works) and `podman-compose`.
- `homelab-firstboot`, which runs a full upgrade once on the VM's first boot
  and then disables itself.
- Root login by key only; no password.
- No machine-id and no SSH host keys, so every VM gets its own.

After that, Debian runs `unattended-upgrades` from the security origin only,
with no automatic reboot. Alpine has no separate security feed; a daily cron
job runs `apk upgrade --available`.

The images hold no keys, hostnames or addresses: the release assets are public.

### Building locally

`build.sh` needs `libguestfs-tools`, so it runs on Linux only. It writes the
image to `images/build/`:

```bash
images/build.sh debian images-test
```

`check.sh` checks a built image's contents:

```bash
images/check.sh debian images/build/debian-13-homelab-images-test.qcow2
```

The unit tests run anywhere:

```bash
bash images/tests/test_lib.sh
```

```bash
bash images/tests/test_check.sh
```

## If the state is lost

Nothing is lost on the host. Start a fresh state and import each container by
node and VM ID:

```bash
op run --env-file=.env.op -- tofu import 'module.example.proxmox_virtual_environment_container.this' venus/120
```

A VM is the same, with its own resource type:

```bash
op run --env-file=.env.op -- tofu import 'module.example.proxmox_virtual_environment_vm.this' venus/130
```
