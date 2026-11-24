# Proxmox VM module: design

Date: 2026-11-24. Status: approved by the owner on 2026-11-24. Second revision:
first-boot configuration moved from cloud-init snippets to pre-baked images
built in CI, at the owner's request.

## Intent

`proxmox/` already declares LXC containers on the Proxmox host (`modules/lxc`,
PR #45). The next guests are virtual machines: pgBackWeb for the off-cluster
PostgreSQL backups (epic #36) first, others later. This adds `modules/vm`, a
reusable module that declares one VM from a ready-made image, so that a VM is
one `module` block in `proxmox/vms.tf` the way a container is one block in
`containers.tf`.

The images are this repo's own: the upstream Debian and Alpine cloud images
with the guest agent, Podman and update policy already installed, built by a
GitHub Actions workflow every week and published as release assets. The
Proxmox node downloads them through its API, so nothing ever SSHes to the node
and tofu writes no file there. Proxmox's native cloud-init does the rest: root
key, hostname, network.

Alpine arrives here rather than as LXC: no public Alpine LXC template ships an
SSH server and cloud-init has no data source inside Proxmox LXC, but Alpine's
official cloud images do both.

## Goals

- One module block declares a Debian 13 or Alpine 3.23 VM on `venus`, with the
  `proxmox-guest-root` key for root, no password, DHCP by default.
- Every VM comes up with the QEMU guest agent running, so Proxmox shows its
  address and shuts it down cleanly, and tofu's agent wait puts the address in
  the outputs.
- Every VM is fully upgraded when it first boots and keeps itself patched
  afterwards without anyone logging in.
- Every VM can run containers: Podman with the Docker CLI shim and
  `podman-compose`, so `docker ...` commands and `compose.yaml` files work as
  written (owner: Podman rather than Docker).
- The images are rebuilt weekly from upstream so a new VM starts close to
  current, and a rebuild is a tag bump in tofu, never a change to running VMs.
- Pure API from the laptop to Proxmox: `op run --env-file=.env.op -- tofu
  apply`, same as containers. No SSH from tofu to the node or to the guests.
- Proven end to end the way the containers were: one throwaway Debian VM and
  one throwaway Alpine VM created, SSH as root verified, guest agent reporting
  verified, `docker run hello-world` verified, both destroyed before merge.

## Non-goals

- pgBackWeb itself, PostgreSQL, NAS mounts, traefik exposure: those are the
  phases of epic #36 and build on this afterwards.
- Moving tofu state off the laptop (deferred, see `proxmox/README.md`).
- UEFI, TPM, GPU or disk passthrough, multiple NICs, extra data disks. Later
  VMs add options when they need them.
- Per-VM opt-in of Podman. It is in every image; a VM that does not use it
  loses a few hundred MB of disk, which is cheaper than two image lines.
- Replacing a VM because its image, keys or anything first-boot changed (see
  Decisions).
- Boot-testing images in CI. The build checks the image contents; the real
  boot test is the tofu proving step on venus.

## Anti-goals

- Any SSH from tofu: to the node (file writes on the hypervisor) or to guests.
- Automatic reboots after unattended updates. A backup VM rebooting itself
  mid-job is worse than a pending kernel update.
- Secrets or private hostnames in images, in the workflow or in the release.
  The repo is public and the release assets are public; the images must be
  safe to hand to anyone.

## Constraints

- Provider `bpg/proxmox` 0.123.1 (pinned); OpenTofu >= 1.10; Proxmox VE 8.4 on
  node `venus`, datastores `local` (dir) and `local-lvm` (lvmthin), bridge
  `vmbr0`, some existing guests tagged VLAN 40.
- API auth is the `opentofu@pve!tofu` token from 1Password, only. The
  `OpenTofu` role has the LXC privileges plus `Datastore.Allocate`; VM
  creation needs more (`VM.Config.CDROM`, `VM.Config.Cloudinit`,
  `VM.Config.HWType` at least). The builder extends the role on the node and in
  the README, letting a `403` name anything still missing, as before.
- The node downloads images by URL (`proxmox_download_file`). Importing a
  qcow2 as a VM disk needs either the `import` content type on `local`
  (PVE 8.4 supports it; one-off `pvesm set local --content ...,import`) or the
  older trick of downloading as `iso` with a `.img` name. The builder picks
  whichever provider 0.123.1 supports cleanly and documents the one-off step.
- Release assets are limited to 2 GB each; the images are a few hundred MB.
- GitHub Actions `ubuntu-latest` runners can run `libguestfs-tools`
  (`virt-customize`, `virt-sysprep`, `virt-sparsify`) without KVM; builds take
  minutes, not hours.
- Public repo: no hostnames, domains or secrets. RFC1918 addresses are fine.
  Downloading from `github.com` release URLs is fine.
- Who runs what: the builder (this session) runs everything, including the
  one-off root steps and read-only checks on venus over the laptop's existing
  root SSH access; `tofu plan`/`apply` and the guest SSH checks run from the
  owner's Terminal panel because the 1Password agent signs only there.
- Branching (owner): the VM branch stacks on the PR #45 branch
  (`claude/epic-wozniak-7uqv8r`) and is rebased when that branch changes; its
  PR waits behind #45. The images workflow can be exercised from the branch
  with a manual run before anything merges.

## Approaches considered

1. **Per-VM cloud-init vendor snippet rendered by tofu.** Idiomatic Proxmox,
   but the API cannot upload snippets, so tofu must SSH to the node and write
   a file on the hypervisor. The owner rejected tofu writing files on the node,
   as root or as a restricted user.
2. **Pre-baked images built in CI** (chosen). A weekly GitHub Actions job
   customises the upstream cloud images and publishes them as release assets;
   the node downloads them by URL; Proxmox native cloud-init handles identity.
   Pure API, fast first boot, VMs are born patched. Cost: a workflow to
   maintain and Podman in every image. Accepted.
3. **Tofu configures the guest over SSH.** No node access and no pipeline,
   but static IPs everywhere, the laptop in the apply path, and run-once
   provisioners Proxmox knows nothing about. Rejected.

## Decisions

Owner decisions are marked (owner); the rest are the designer's calls, with
reasons, for the owner to correct.

### Images (`images/` and `.github/workflows/images.yml`)

- Two images: `debian-13-homelab-amd64.qcow2` from Debian 13 (trixie)
  `genericcloud` amd64 (owner: Debian), and `alpine-3.23-homelab-x86_64.qcow2`
  from Alpine's official 3.23 cloud image, the cloud-init (`nocloud`) x86_64
  BIOS variant (owner: Alpine via the official cloud images; designer:
  cloud-init rather than Tiny Cloud because Proxmox presents a NoCloud data
  source and it matches Debian).
- Built by `images/build.sh <distribution>` so the same script runs locally
  and in CI. It downloads the upstream image (verifying the upstream checksum),
  runs `virt-customize` to install and configure (below), `virt-sysprep` to
  strip machine identity (machine-id, SSH host keys, cloud-init state, logs) so
  every VM is unique, then `virt-sparsify --compress`.
- Installed in both: `qemu-guest-agent` (enabled), `podman`, `podman-docker`
  (the `docker` shim), `podman-compose`, rootful, with the Docker-compatible API
  socket enabled (`podman.socket` on Debian; the `podman` OpenRC service on
  Alpine, plus cgroups v2: `rc_cgroup_mode="unified"` and the `cgroups`
  service). Unqualified image names resolve to `docker.io` (Debian's containers
  config already does; the Alpine image gets `unqualified-search-registries`
  set). All packages come from the distributions' own repositories, so their
  update channels cover them.
- Updates at build: the build runs a full upgrade (`apt-get dist-upgrade` /
  `apk upgrade`) so each weekly image is current on its build day.
- Updates at first boot (owner: `apt update && apt upgrade` on a new VM): a
  baked one-shot service, `homelab-firstboot`, runs a full upgrade once on the
  VM's first boot and then disables itself (systemd unit with a condition on a
  marker file under `/var/lib/homelab/`; an OpenRC service doing the same on
  Alpine). Designer's call: a one-shot in the image replaces what cloud-init
  vendor data would have done, and keeps the owner's requirement without any
  file on the node.
- Updates afterwards (owner: security updates out of the box):
  - Debian: `unattended-upgrades` limited to the
    `${distro_id}:${distro_codename}-security` origin, `Automatic-Reboot
    "false"`, standard apt-daily timers. Designer's call: security only, so a
    point release does not change packages under a running service. Podman is
    Debian's own package, so this covers it.
  - Alpine: no separate security feed exists; the stable branch receives only
    fixes. A daily cron job runs `apk update && apk upgrade --available`,
    logging to syslog. Designer's call, reasoned above.
- Root login: the images keep root enabled for key login (`PermitRootLogin
  prohibit-password`), so Proxmox native cloud-init's `user_account {
  username = "root", keys }` works on both. Debian's genericcloud honours a
  root user account; the Alpine image's cloud-init config must be checked and
  adjusted in the build if it locks root (builder, see Left to the builder).
- Workflow (owner: weekly): `.github/workflows/images.yml` runs on
  `schedule` once a week, on `workflow_dispatch`, and on `push` to any branch
  that changes `images/**` or the workflow. Each run builds both images on
  `ubuntu-latest`, checks their contents (`virt-ls`/`virt-cat`: the packages
  are installed, the services enabled, sysprep left no machine-id), writes
  `SHA256SUMS`, and publishes a GitHub Release tagged `images-YYYYMMDD` with
  the two qcow2 files and the checksums. Runs from a non-default branch
  publish a pre-release so the proving step can use them without touching the
  normal tags. Designer's calls: a date tag so a tofu variable can pin a build
  by eye; a release per run rather than overwriting one `latest` so a bad
  build is a tag bump back, not a lost image.
- Retention: the workflow keeps the last 8 scheduled/master image releases and
  the last 2 branch pre-releases, and never deletes the release whose tag
  `proxmox/variables.tf` currently pins (the workflow reads `images_release`
  from the checkout). Designer's call; the numbers are variables in the
  workflow. So an old pin keeps downloading and the images behind running VMs
  stay available for a re-import.
- Schedule caveat: GitHub pauses scheduled workflows after 60 days without
  commits. This repo sees regular commits; the README notes that a missing
  weekly release means the schedule needs re-enabling under Actions.
- The images contain nothing from this homelab except the update policy and
  package choices: no keys, no hostnames, no addresses.

### Module interface (`modules/vm`)

Required: `hostname`, `vm_id`, `node_name`, `datastore_id`, `bridge`,
`image_file_id` (the id of a `proxmox_download_file` for the chosen image),
`ssh_public_keys`.

Optional, with defaults: `cores = 1` (owner), `memory = 2048` (MB), `disk_size = 16`
(GB), `ipv4_address = "dhcp"`, `ipv4_gateway = null`, `vlan_id = null`,
`started = true`, `start_on_boot = true`, `tags = []`, `description`.

Outputs: `vm_id`, `ipv4` (from the guest agent).

Fixed inside the module: `agent { enabled = true }`, machine `q35`, SeaBIOS
(the Alpine image is a BIOS build; Debian boots either way), CPU type
`x86-64-v2-AES`, `virtio-scsi-single`, serial console on (cloud images expect
one), a cloud-init drive on the same datastore, tag `opentofu` always added
and tags normalised like the LXC module, `on_boot` from `start_on_boot`, the
root disk imported from the image and resized to `disk_size`.

Native cloud-init only: `initialization { user_account { username = "root",
keys } ip_config { ipv4 { address, gateway } } }`. No user, vendor or
network snippets, anywhere.

`lifecycle { ignore_changes }` covers the imported image and the keys, so a
newer image tag or a rotated key applies to VMs created afterwards and never
replaces an existing one. This mirrors the LXC module. The README says so.

### Root module wiring

- `proxmox/images.tf`: two `proxmox_download_file` resources (Debian, Alpine)
  pointing at release asset URLs of this repo, with `file_name` carrying the
  release tag (e.g. `debian-13-homelab-images-20261124.qcow2`) so a bump is a
  new file beside the old one, and `overwrite = false` so tofu never re-checks
  the URL once the file is on the node. A root variable `images_release` (the
  `images-YYYYMMDD` tag) builds both URLs; bumping it is the one-line change
  that gives new VMs a newer image. At merge it pins the branch pre-release the
  proving step used; the first scheduled master release is a follow-up bump.
- `proxmox/vms.tf`: every VM is one module block. During the proving step it
  holds `tofu-vm-debian` (vm_id 9101) and `tofu-vm-alpine` (vm_id 9102),
  tagged `test`, removed before merge as the containers were.
- `providers.tf` unchanged: no `ssh` block.
- README: a "Virtual machines" section (adding a VM, what is in the images,
  where the agent address shows up, bumping `images_release`), an "Images"
  section pointing at `images/` and the workflow, and the new one-off node
  steps (`import` content on `local` if used, the extra role privileges).

### Verification before merge

1. Run the images workflow from the branch; both images publish as a
   pre-release; the content checks pass.
2. `tofu fmt -check -recursive`, `tofu validate`.
3. Plan then apply the two test VMs pinned to that pre-release; expected:
   2 downloads, 2 VMs.
4. On the node: `qm agent 9101 network-get-interfaces` and the same for 9102
   return addresses; `qm config` shows the cloud-init drive and no `cicustom`.
5. From the laptop, in the owner's own terminal (the 1Password agent will not
   sign for the sandboxed shell): `ssh root@<ip>` into both; the firstboot
   service has run and disabled itself; `docker run --rm hello-world` and a
   one-service `podman-compose up` work on both; `systemctl status
   unattended-upgrades` on Debian and the cron entry on Alpine.
6. Destroy the two VMs via code removal and apply; confirm `qm list` and state.
7. Commit on the stacked branch; open its PR as a draft before #45 merges, or
   against master after.

## Left to the builder

- Exact upstream image URLs and checksum files current on the build day, and
  how `build.sh` pins them (Debian publishes `latest` plus dated directories;
  Alpine publishes per-release files).
- The import route per the provider version (see Constraints).
- Exact extra privileges for the role; the 403 names them.
- Whether `virt-customize` handles the Alpine image's `apk` without help on
  `ubuntu-latest`; if not, the Alpine build mounts the image with `qemu-nbd`
  and runs `apk` in a chroot, inside the same `build.sh`.
- Whether the Alpine cloud image's cloud-init config locks root, and the
  build-time fix if so; if root cannot be made to work, fall back to the
  image's default user plus `doas`/`sudo` and flag it to the owner.
- Timeouts on the VM resource (agent wait, create, shutdown) sized so the
  first-boot upgrade does not fail the apply.
- Whether `podman-docker`'s shim and `podman-compose` behave with pgBackWeb's
  published compose file; if not, the compose fallback is Podman's quadlet
  units, flagged to the owner before use.
