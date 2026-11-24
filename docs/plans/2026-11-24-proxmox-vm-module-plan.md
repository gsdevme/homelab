# Proxmox VM module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Declare Debian 13 and Alpine 3.23 virtual machines on the Proxmox host from `proxmox/` with one module block each, booting from this repo's own weekly-built images that already carry the QEMU guest agent, Podman and the update policy.

**Architecture:** A GitHub Actions workflow customises the upstream cloud images with libguestfs and publishes them as GitHub Release assets tagged `images-YYYYMMDD`. `proxmox/images.tf` has the node download the two assets through the Proxmox API (`content_type = "import"`); `modules/vm` imports one as the root disk and lets Proxmox's native cloud-init set root key, hostname and network. No SSH from tofu anywhere.

**Tech Stack:** OpenTofu >= 1.10, `bpg/proxmox` 0.123.1, Proxmox VE 8.4, GitHub Actions on `ubuntu-latest`, `libguestfs-tools` (`virt-customize`, `virt-sysprep`, `virt-sparsify`, `virt-cat`, `virt-ls`), `gh` CLI, bash.

**Spec:** `docs/plans/2026-11-24-proxmox-vm-module-design.md`

## Global Constraints

- Provider pinned to `bpg/proxmox` 0.123.1; no provider `ssh` block, no snippets, no `*_data_file_id`.
- Node `venus`; datastores `local` (images, `import` content) and `local-lvm` (VM disks); bridge `vmbr0`.
- Secrets only via `op run --env-file=.env.op`. Nothing private in images, workflow or releases; the repo is public. RFC1918 addresses may be committed; hostnames and domains may not.
- `tofu plan`/`apply` and guest `ssh` run from the owner's Terminal panel (1Password agent); node commands run from the builder's shell as `root@172.16.16.91`.
- Branch `proxmox-vm-module` stacked on `claude/epic-wozniak-7uqv8r`. Nothing is pushed, and no PR or issue is touched, without the owner's explicit go-ahead; the workflow needs a push, so Task 5 has a checkpoint.
- Commits: Conventional Commits, one atomic commit per task; squash fixups into the task's commit.
- Comments: doc blocks over inline comments in shell and HCL; YAML is commented generously.
- Images: Podman always installed; cores default `1`, memory `2048`, disk `16`; no automatic reboots; `unattended-upgrades` security origin only on Debian; daily `apk upgrade --available` on Alpine.

## Review Focus

1. Upstream listing drift: Debian renames a file or Alpine publishes 3.24; `build.sh` must fail with a clear message, never build a wrong image. (Task 2 and 3 tests: `resolve_*` functions exit non-zero on a listing with no match.)
2. Leftover machine identity: a baked `/etc/machine-id` or SSH host key would give every VM the same DHCP identity and host key. (Task 4 verify step: `virt-cat` of `/etc/machine-id` is empty, `virt-ls /etc/ssh` has no `ssh_host_*`.)
3. Alpine root login: the cloud image may lock root or set `disable_root: true`, so the key lands but login fails. (Task 3: the build writes a cloud.cfg.d override and the content check asserts it; Task 7 verifies `ssh root@` on Alpine.)
4. A second download with the same `file_name` already on the node (re-import after state loss) errors with `overwrite_unmanaged = false`. (Task 6: `overwrite_unmanaged = true` on both download resources, documented.)
5. First-boot upgrade racing the agent wait: a slow `dist-upgrade` can outlast the default agent timeout and fail the apply even though the VM is fine. (Task 6: `agent { timeout = "15m" }`, `timeout_create = 1800`; Task 7 confirms apply completes while the upgrade runs.)

---

### Task 1: Branch and design doc

**Files:**
- Commit: `docs/plans/2026-11-24-proxmox-vm-module-design.md`, `docs/plans/2026-11-24-proxmox-vm-module-plan.md`

- [ ] **Step 1: Create the stacked branch**

Run: `git -C /Users/gavin/Sites/homelab switch -c proxmox-vm-module claude/epic-wozniak-7uqv8r`
Expected: `Switched to a new branch 'proxmox-vm-module'`; `git log --oneline -1` shows `feat(proxmox): manage LXC containers on the Proxmox host with OpenTofu`.

- [ ] **Step 2: Commit the design and this plan**

```bash
git add docs/plans/2026-11-24-proxmox-vm-module-design.md docs/plans/2026-11-24-proxmox-vm-module-plan.md
git commit -m "docs(proxmox): design and plan for the VM module and weekly images"
```

---

### Task 2: Debian image build script

**Files:**
- Create: `images/build.sh` (entry point, `bash`, `set -euo pipefail`)
- Create: `images/lib.sh` (shared functions sourced by `build.sh` and tests)
- Create: `images/debian/customize.sh` (runs inside the guest via `virt-customize --run`)
- Create: `images/debian/50unattended-upgrades-homelab` (apt conf), `images/debian/20auto-upgrades-homelab` (apt conf), `images/debian/homelab-firstboot.service`, `images/debian/homelab-firstboot.sh`
- Create: `images/tests/test_lib.sh` (bash tests, no network: feed fixture HTML/SHA files)
- Create: `images/tests/fixtures/debian-listing.html`, `images/tests/fixtures/debian-SHA512SUMS`
- Modify: `.gitignore` (add `images/build/`)

**Interfaces:**
- Produces, in `images/lib.sh`:
  - `resolve_debian <listing_html_file> <sha512sums_file>` → prints two lines: `<url>` of `debian-13-genericcloud-amd64.qcow2` under `https://cloud.debian.org/images/cloud/trixie/latest/` and its sha512 from `SHA512SUMS`; exit 1 with `no genericcloud amd64 qcow2 in listing` / `no checksum for <file>` when absent.
  - `fetch_verified <url> <sha512> <dest>` → downloads with `curl -fsSL`, verifies `sha512sum`, exits 1 on mismatch.
  - `output_name <distribution> <tag>` → prints `debian-13-homelab-<tag>.qcow2` or `alpine-3.23-homelab-<tag>.qcow2`.
- Produces: `images/build.sh <debian|alpine> <tag>` writes `images/build/<output_name>` and `images/build/<output_name>.sha256`. Tag is `images-YYYYMMDD` (the workflow passes it; locally anything).
- Debian customize contract (what Task 4's content check asserts): packages `qemu-guest-agent podman podman-docker podman-compose unattended-upgrades` installed; `qemu-guest-agent.service`, `podman.socket`, `homelab-firstboot.service`, `unattended-upgrades.service` enabled; `/etc/apt/apt.conf.d/50unattended-upgrades-homelab` contains `"origin=Debian,codename=${distro_codename}-security";` and `Unattended-Upgrade::Automatic-Reboot "false";`; `/etc/apt/apt.conf.d/20auto-upgrades-homelab` has `APT::Periodic::Update-Package-Lists "1";` and `APT::Periodic::Unattended-Upgrade "1";`; `/etc/ssh/sshd_config.d/10-homelab-root.conf` contains `PermitRootLogin prohibit-password`; `/etc/cloud/cloud.cfg.d/90-homelab.cfg` contains `disable_root: false`; `/var/lib/homelab/` exists and is empty.

- [ ] **Step 1: Write the failing tests**

`images/tests/test_lib.sh` (plain bash, `set -euo pipefail`, each test a function, a `fail()` helper, runs all and exits non-zero on any failure):

```bash
test_resolve_debian_finds_qcow2_and_sum() {
  out=$(resolve_debian fixtures/debian-listing.html fixtures/debian-SHA512SUMS)
  [[ "$(sed -n 1p <<<"$out")" == "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2" ]] || fail "url"
  [[ "$(sed -n 2p <<<"$out")" == "0123456789abcdef$(printf 'ab%.0s' {1..56})" ]] || fail "sum"
}
test_resolve_debian_fails_without_match() {
  ! resolve_debian fixtures/empty.html fixtures/debian-SHA512SUMS 2>/dev/null || fail "should exit non-zero"
}
test_output_name() {
  [[ "$(output_name debian images-20261124)" == "debian-13-homelab-images-20261124.qcow2" ]] || fail "debian name"
  [[ "$(output_name alpine images-20261124)" == "alpine-3.23-homelab-images-20261124.qcow2" ]] || fail "alpine name"
}
test_fetch_verified_rejects_bad_sum() {
  ! fetch_verified "file://$PWD/fixtures/debian-SHA512SUMS" deadbeef "$tmp/x" 2>/dev/null || fail "bad sum accepted"
}
```

Fixtures: `debian-listing.html` is a trimmed copy of the real `trixie/latest/` index with the three qcow2 anchors; `debian-SHA512SUMS` has one line per file with the 128-hex fake sum above for the genericcloud qcow2; `empty.html` is an index with no qcow2 anchors.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash /Users/gavin/Sites/homelab/images/tests/test_lib.sh`
Expected: FAIL, `lib.sh: No such file or directory`.

- [ ] **Step 3: Implement `images/lib.sh`**

`resolve_debian` greps the anchor `debian-13-genericcloud-amd64.qcow2` from the listing (`grep -o 'href="debian-13-genericcloud-amd64.qcow2"'`) and the matching line from `SHA512SUMS` (`awk '$2 == "debian-13-genericcloud-amd64.qcow2" {print $1}'`). `fetch_verified` uses `curl -fsSL --retry 3 -o`, then `printf '%s  %s\n' "$sum" "$dest" | sha512sum -c --quiet`. `output_name` is a `case`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash /Users/gavin/Sites/homelab/images/tests/test_lib.sh`
Expected: `4 passed`.

- [ ] **Step 5: Write the Debian customisation files**

`images/debian/customize.sh` (runs as root inside the image; `set -euo pipefail`; `export DEBIAN_FRONTEND=noninteractive`): `apt-get update`, `apt-get -y dist-upgrade`, `apt-get -y install qemu-guest-agent podman podman-docker podman-compose unattended-upgrades`, `systemctl enable qemu-guest-agent podman.socket homelab-firstboot unattended-upgrades`, `mkdir -p /var/lib/homelab`, `apt-get clean`. The config files are copied in by `build.sh` with `--copy-in` before `--run` (see Step 6), so `customize.sh` only installs and enables.

`images/debian/50unattended-upgrades-homelab`:
```
Unattended-Upgrade::Origins-Pattern { "origin=Debian,codename=${distro_codename}-security"; };
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
```
`images/debian/20auto-upgrades-homelab`: the two `APT::Periodic` lines from the Interfaces block.

`images/debian/homelab-firstboot.service`: `[Unit] Description=Full upgrade on first boot`, `After=network-online.target cloud-final.service`, `Wants=network-online.target`, `ConditionPathExists=!/var/lib/homelab/firstboot-done`; `[Service] Type=oneshot ExecStart=/usr/local/sbin/homelab-firstboot`; `[Install] WantedBy=multi-user.target`.

`images/debian/homelab-firstboot.sh`: `apt-get update && apt-get -y dist-upgrade && apt-get -y autoremove && touch /var/lib/homelab/firstboot-done`.

Common files used by both distributions, in `images/common/`: `10-homelab-root.conf` (`PermitRootLogin prohibit-password`), `90-homelab.cfg` (`disable_root: false`).

- [ ] **Step 6: Implement `images/build.sh`**

Signature: `build.sh <debian|alpine> <tag>`. Flow: `source lib.sh`; `mkdir -p build`; for `debian`: `curl` the listing and `SHA512SUMS` to `build/`, `resolve_debian`, `fetch_verified` to `build/upstream-debian.qcow2`, `cp` to `build/<output_name>`; `virt-customize -a <out> --copy-in images/debian/50unattended-upgrades-homelab:/etc/apt/apt.conf.d --copy-in ...20auto-upgrades-homelab:/etc/apt/apt.conf.d --copy-in images/debian/homelab-firstboot.service:/etc/systemd/system --copy-in images/debian/homelab-firstboot.sh:/usr/local/sbin --run-command 'mv /usr/local/sbin/homelab-firstboot.sh /usr/local/sbin/homelab-firstboot && chmod 755 /usr/local/sbin/homelab-firstboot' --copy-in images/common/10-homelab-root.conf:/etc/ssh/sshd_config.d --copy-in images/common/90-homelab.cfg:/etc/cloud/cloud.cfg.d --run images/debian/customize.sh`; then `virt-sysprep -a <out> --operations defaults,-ssh-userdir --enable ...` is wrong: use `virt-sysprep -a <out>` (defaults include `machine-id`, `ssh-hostkeys`, `cloud-init` state, logs) and keep `--operations defaults`; then `virt-sparsify --compress --in-place <out>`; finally `sha256sum <out> > <out>.sha256`. Alpine branch is Task 3; until then `alpine` exits 2 with `not implemented`.

- [ ] **Step 7: Lint**

Run: `bash -n images/build.sh images/lib.sh images/debian/customize.sh images/debian/homelab-firstboot.sh && shellcheck images/*.sh images/debian/*.sh images/tests/*.sh` (install shellcheck with `brew install shellcheck` if missing).
Expected: no output.

- [ ] **Step 8: Add `images/build/` to `.gitignore` and commit**

```bash
git add .gitignore images/
git commit -m "build(images): Debian 13 image with guest agent, Podman and update policy"
```

---

### Task 3: Alpine image build

**Files:**
- Modify: `images/lib.sh`, `images/build.sh`
- Create: `images/alpine/customize.sh`, `images/alpine/homelab-firstboot` (OpenRC script), `images/alpine/homelab-upgrade.cron`
- Create: `images/tests/fixtures/alpine-listing.html`
- Modify: `images/tests/test_lib.sh`

**Interfaces:**
- Produces, in `images/lib.sh`: `resolve_alpine <listing_html_file>` → prints `<url>` of the newest `alpine-3.23.N-x86_64-bios-cloudinit-rM.qcow2` under `https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/` (highest N then M, `sort -V`), and its checksum URL `<url>.sha512`; exit 1 with `no 3.23 bios cloudinit x86_64 qcow2 in listing` when absent. The `.sha512` file's first field is the sum.
- Alpine customize contract (asserted by Task 4): packages `qemu-guest-agent podman podman-docker podman-compose` installed (`apk info -e`); `rc-update show default` lists `qemu-guest-agent podman cgroups crond homelab-firstboot` (`cgroups` may be in `sysinit`; the check accepts either); `/etc/rc.conf` contains `rc_cgroup_mode="unified"`; `/etc/containers/registries.conf` contains `unqualified-search-registries = ["docker.io"]`; `/etc/periodic/daily/homelab-upgrade` is executable and runs `apk update && apk upgrade --available`; the two common files from Task 2 are present; `/var/lib/homelab/` exists and is empty.

- [ ] **Step 1: Write the failing tests**

```bash
test_resolve_alpine_picks_newest_bios_cloudinit() {
  out=$(resolve_alpine fixtures/alpine-listing.html)
  [[ "$(sed -n 1p <<<"$out")" == "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/alpine-3.23.8-x86_64-bios-cloudinit-r0.qcow2" ]] || fail "url"
  [[ "$(sed -n 2p <<<"$out")" == "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/alpine-3.23.8-x86_64-bios-cloudinit-r0.qcow2.sha512" ]] || fail "sha url"
}
test_resolve_alpine_ignores_uefi_metal_and_other_arch() {
  # fixture also lists 3.23.9 uefi, 3.23.9 bios-cloudinit-metal and aarch64 3.23.9 bios: none may win
}
test_resolve_alpine_fails_without_match() { ! resolve_alpine fixtures/empty.html 2>/dev/null || fail "should exit non-zero"; }
```

Fixture `alpine-listing.html`: anchors for `alpine-3.23.7-x86_64-bios-cloudinit-r0.qcow2`, `alpine-3.23.7-x86_64-bios-cloudinit-r1.qcow2`, `alpine-3.23.8-x86_64-bios-cloudinit-r0.qcow2`, `alpine-3.23.9-x86_64-uefi-cloudinit-r0.qcow2`, `alpine-3.23.9-x86_64-bios-cloudinit-metal-r0.qcow2`, `alpine-3.23.9-aarch64-bios-cloudinit-r0.qcow2`, plus matching `.sha512` anchors.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash images/tests/test_lib.sh`
Expected: FAIL, `resolve_alpine: command not found`.

- [ ] **Step 3: Implement `resolve_alpine` in `images/lib.sh`**

`grep -o 'alpine-3\.23\.[0-9]*-x86_64-bios-cloudinit-r[0-9]*\.qcow2' | sort -uV | tail -1`; empty → error.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash images/tests/test_lib.sh`
Expected: `7 passed`.

- [ ] **Step 5: Write the Alpine customisation files**

`images/alpine/customize.sh`: `apk update && apk upgrade --available`; `apk add qemu-guest-agent podman podman-docker podman-compose`; `rc-update add qemu-guest-agent default; rc-update add podman default; rc-update add cgroups sysinit; rc-update add crond default; rc-update add homelab-firstboot default`; `sed -i 's/^#\?rc_cgroup_mode=.*/rc_cgroup_mode="unified"/' /etc/rc.conf` (append if absent); write `unqualified-search-registries = ["docker.io"]` to `/etc/containers/registries.conf`; `mkdir -p /var/lib/homelab`; `chmod 755 /etc/periodic/daily/homelab-upgrade /etc/init.d/homelab-firstboot`. If the Alpine image's `/etc/cloud/cloud.cfg` sets `disable_root: true`, the common `90-homelab.cfg` overrides it (cloud.cfg.d wins); if its `users:` default has no `root`, nothing else is needed since Proxmox's user-data names the user.

`images/alpine/homelab-firstboot` (OpenRC, `#!/sbin/openrc-run`, `depend() { need net; after cloud-final; }`, `start()` runs `apk update && apk upgrade --available && touch /var/lib/homelab/firstboot-done` only when the marker is absent, then `rc-update del homelab-firstboot default`).

`images/alpine/homelab-upgrade.cron` (installed as `/etc/periodic/daily/homelab-upgrade`): `#!/bin/sh` `apk update >/dev/null && apk upgrade --available 2>&1 | logger -t homelab-upgrade`.

- [ ] **Step 6: Add the `alpine` branch to `build.sh`**

Download listing, `resolve_alpine`, `curl` the `.sha512`, `fetch_verified`, then `virt-customize -a <out> --copy-in images/alpine/homelab-firstboot:/etc/init.d --copy-in images/alpine/homelab-upgrade.cron:/tmp --run-command 'mv /tmp/homelab-upgrade.cron /etc/periodic/daily/homelab-upgrade' --copy-in images/common/10-homelab-root.conf:/etc/ssh/sshd_config.d --copy-in images/common/90-homelab.cfg:/etc/cloud/cloud.cfg.d --run images/alpine/customize.sh`, then the same `virt-sysprep` and `virt-sparsify` as Debian. If Alpine's sshd lacks an `Include /etc/ssh/sshd_config.d/*.conf` line, `customize.sh` appends it to `/etc/ssh/sshd_config`.

- [ ] **Step 7: Lint and commit**

Run: `shellcheck images/*.sh images/alpine/*.sh images/debian/*.sh images/tests/*.sh`; Expected: no output.

```bash
git add images/
git commit -m "build(images): Alpine 3.23 image with guest agent, Podman and daily upgrades"
```

---

### Task 4: Image content checks

**Files:**
- Create: `images/check.sh` (`check.sh <debian|alpine> <image>`; exits non-zero on the first failed assertion, printing which)

**Interfaces:**
- Consumes the customize contracts from Tasks 2 and 3.
- Produces: `images/check.sh` used by the workflow after each build.

- [ ] **Step 1: Implement `images/check.sh`**

A `has_file <path>` (`virt-ls -a "$img" "$(dirname "$path")" | grep -qx "$(basename "$path")"`), `file_contains <path> <string>` (`virt-cat -a "$img" "$path" | grep -qF -- "$string"`), `no_file <path>`. Debian: the Interfaces list from Task 2 plus `has_file /var/lib/dpkg/info/podman.list` (and the other four packages), `file_contains /etc/systemd/system/multi-user.target.wants/homelab-firstboot.service homelab-firstboot` via `virt-ls` of the wants dirs, `no_file /var/lib/homelab/firstboot-done`. Alpine: `file_contains /etc/apk/world podman` (and the others), `has_file /etc/runlevels/default/qemu-guest-agent` etc., `file_contains /etc/rc.conf 'rc_cgroup_mode="unified"'`, `file_contains /etc/containers/registries.conf docker.io`. Both: `virt-cat /etc/machine-id` is empty or absent, `virt-ls /etc/ssh | grep -c ssh_host_` is 0, `has_file /etc/ssh/sshd_config.d/10-homelab-root.conf`, `has_file /etc/cloud/cloud.cfg.d/90-homelab.cfg`.

- [ ] **Step 2: Lint and commit**

Run: `shellcheck images/check.sh`; Expected: no output.

```bash
git add images/check.sh
git commit -m "build(images): content checks for the built images"
```

---

### Task 5: Weekly workflow, release and retention

**Files:**
- Create: `.github/workflows/images.yml`
- Create: `images/prune-releases.sh`
- Modify: `images/tests/test_lib.sh` (tests for the prune selection function), `images/lib.sh` (`select_prunable`)

**Interfaces:**
- Produces: GitHub Releases tagged `images-YYYYMMDD` (pre-release when `github.ref_name != master`) with assets `debian-13-homelab-images-YYYYMMDD.qcow2`, `alpine-3.23-homelab-images-YYYYMMDD.qcow2`, `SHA256SUMS`. Task 6 builds URLs as `https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>`.
- Produces, in `images/lib.sh`: `select_prunable <keep_releases> <keep_prereleases> <pinned_tag>` reading `gh release list` JSON (`tagName`, `isPrerelease`, `createdAt`) on stdin, printing the tags to delete, newest kept first, never the pinned tag, never tags not starting with `images-`.
- Produces: `images/prune-releases.sh` reads the pin with `grep -o 'images-[0-9]\{8\}' proxmox/variables.tf | head -1` and deletes with `gh release delete <tag> --cleanup-tag --yes`.

- [ ] **Step 1: Write the failing tests for `select_prunable`**

```bash
test_select_prunable_keeps_latest_and_pinned() {
  # 10 releases images-20260101..images-20260110 (non-pre), 3 pre images-20260201..03, pin images-20260102
  out=$(printf '%s' "$fixture_json" | select_prunable 8 2 images-20260102)
  [[ "$out" == $'images-20260101' ]] || fail "expected only the oldest unpinned release, got: $out"  # 20260102 pinned, 20260103.. kept as 8 newest
}
test_select_prunable_prunes_old_prereleases() {
  out=$(printf '%s' "$fixture_json" | select_prunable 8 1 images-20260110)
  grep -qx images-20260201 <<<"$out" && grep -qx images-20260202 <<<"$out" || fail "two oldest pre-releases"
}
test_select_prunable_ignores_foreign_tags() { # a "v1.2.3" release never appears in the output
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash images/tests/test_lib.sh`; Expected: FAIL, `select_prunable: command not found`.

- [ ] **Step 3: Implement `select_prunable` in `images/lib.sh`** (uses `jq`: filter `images-` tags, split by `isPrerelease`, sort by `tagName` descending, drop the first N of each, drop the pinned tag, print the rest).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash images/tests/test_lib.sh`; Expected: `10 passed`.

- [ ] **Step 5: Write `images/prune-releases.sh` and `.github/workflows/images.yml`**

Workflow, commented per the YAML rule: `on: schedule: - cron: "17 3 * * 1"` (Mondays 03:17 UTC), `workflow_dispatch`, `push: paths: [images/**, .github/workflows/images.yml]`. `permissions: contents: write`. One job `build` on `ubuntu-latest`, `strategy.matrix.distribution: [debian, alpine]`: checkout; `sudo apt-get install -y libguestfs-tools qemu-utils`; `sudo chmod 0644 /boot/vmlinuz*` (libguestfs needs a readable kernel on GitHub runners); `TAG=images-$(date -u +%Y%m%d)` written to `$GITHUB_OUTPUT`; `sudo -E images/build.sh ${{ matrix.distribution }} $TAG`; `sudo images/check.sh ${{ matrix.distribution }} images/build/<name>`; `actions/upload-artifact` of `images/build/*.qcow2*`. A second job `release` (`needs: build`): download both artifacts, `sha256sum *.qcow2 > SHA256SUMS`, `gh release create "$TAG" --title "$TAG" --notes "Weekly Proxmox VM images: Debian 13 and Alpine 3.23 with the QEMU guest agent, Podman and the homelab update policy. Built from <sha>." $( [ "$GITHUB_REF_NAME" != master ] && echo --prerelease ) *.qcow2 SHA256SUMS`; if the tag already exists today (`gh release view "$TAG"`), use `gh release upload --clobber` instead. Then `images/prune-releases.sh 8 2`. `GH_TOKEN: ${{ github.token }}`.

- [ ] **Step 6: Lint**

Run: `shellcheck images/prune-releases.sh && python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/images.yml"))'` (or `yq`); Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/images.yml images/
git commit -m "ci(images): build and release Proxmox VM images weekly"
```

- [ ] **Step 8: CHECKPOINT: ask the owner to push the branch**

The workflow can only run on GitHub. Ask: "Push `proxmox-vm-module` so the images workflow can run? It publishes a pre-release tagged images-YYYYMMDD; nothing else." Only on a yes: `git push -u origin proxmox-vm-module`, then `gh run watch` the `images` workflow (run in the background; it takes several minutes). On failure, fix, squash into the Task 2 to 5 commit it belongs to, and push again (`--force-with-lease`) with the owner's standing yes for this branch.

- [ ] **Step 9: Verify the pre-release**

Run: `gh release view images-$(date -u +%Y%m%d) --json isPrerelease,assets --jq '{isPrerelease, assets: [.assets[].name]}'`
Expected: `isPrerelease: true`, three assets named as in Interfaces.

---

### Task 6: `modules/vm`, images and test VMs in tofu

**Files:**
- Create: `proxmox/modules/vm/main.tf`, `proxmox/modules/vm/variables.tf`, `proxmox/modules/vm/outputs.tf`, `proxmox/modules/vm/versions.tf`
- Create: `proxmox/images.tf`, `proxmox/vms.tf`
- Modify: `proxmox/variables.tf` (add `images_repository`, `images_release`, `images_datastore`), `proxmox/outputs.tf` (add `vms` output)

**Interfaces:**
- Consumes: release asset URLs from Task 5.
- Produces, module `modules/vm` variables: `hostname` (string), `vm_id` (number), `node_name`, `datastore_id`, `bridge`, `image_file_id` (string), `ssh_public_keys` (list(string)), `cores = 1`, `memory = 2048`, `disk_size = 16` (validation `>= 8`), `ipv4_address = "dhcp"`, `ipv4_gateway = null`, `vlan_id = null`, `started = true`, `start_on_boot = true`, `tags = []`, `description = "Managed by OpenTofu from proxmox/ in the homelab repo. Do not edit by hand."`. Outputs: `vm_id` (number), `ipv4` (string: the first non-loopback entry of `ipv4_addresses`, or `null`).
- Produces, root: `variable "images_repository"` default `"gsdevme/homelab"`; `variable "images_release"` (string, validation `^images-[0-9]{8}$`, default the pre-release tag from Task 5); `variable "images_datastore"` default `"local"`; `local.image_urls = { debian = "https://github.com/${var.images_repository}/releases/download/${var.images_release}/debian-13-homelab-${var.images_release}.qcow2", alpine = ... }`; resources `proxmox_download_file.debian_vm` and `.alpine_vm` with `content_type = "import"`, `file_name = "debian-13-homelab-${var.images_release}.qcow2"` (resp. alpine), `overwrite = false`, `overwrite_unmanaged = true`, `datastore_id = var.images_datastore`.

- [ ] **Step 1: Write the module**

`main.tf`: `resource "proxmox_virtual_environment_vm" "this"` with `name = var.hostname`, `vm_id`, `node_name`, `description`, `tags = sort(distinct([for t in concat(["opentofu"], var.tags) : lower(t)]))`, `machine = "q35"`, `bios = "seabios"`, `scsi_hardware = "virtio-scsi-single"`, `on_boot = var.start_on_boot`, `started = var.started`, `stop_on_destroy = true`, `timeout_create = 1800`, `timeout_shutdown_vm = 300`; blocks `agent { enabled = true  timeout = "15m" }`, `cpu { cores = var.cores  type = "x86-64-v2-AES" }`, `memory { dedicated = var.memory }`, `disk { datastore_id = var.datastore_id  interface = "scsi0"  import_from = var.image_file_id  size = var.disk_size  discard = "on"  iothread = true }`, `network_device { bridge = var.bridge  vlan_id = var.vlan_id  model = "virtio" }`, `serial_device {}`, `operating_system { type = "l26" }`, `initialization { datastore_id = var.datastore_id  user_account { username = "root"  keys = var.ssh_public_keys }  ip_config { ipv4 { address = var.ipv4_address  gateway = var.ipv4_gateway } } }`, `lifecycle { ignore_changes = [disk[0].import_from, initialization[0].user_account] }`. A doc block at the top of the file explains the ignore list the way `modules/lxc/main.tf` does.

`outputs.tf`: `ipv4 = try([for a in flatten(proxmox_virtual_environment_vm.this.ipv4_addresses) : a if a != "127.0.0.1"][0], null)`.

`versions.tf`: same as `modules/lxc/versions.tf`.

- [ ] **Step 2: Write `images.tf`, `vms.tf`, root variables and outputs**

`vms.tf`: `locals { test_vms = { tofu-vm-debian = { vm_id = 9101, image = proxmox_download_file.debian_vm.id }, tofu-vm-alpine = { vm_id = 9102, image = proxmox_download_file.alpine_vm.id } } }` and `module "test_vm"` with `for_each`, `tags = ["test"]`, the root facts, `ssh_public_keys = [trimspace(var.ssh_public_key)]`. `outputs.tf`: `output "vms"` mapping name to `{ vm_id, ipv4 }`.

- [ ] **Step 3: Format and validate**

Run: `tofu -chdir=/Users/gavin/Sites/homelab/proxmox fmt -recursive && tofu -chdir=/Users/gavin/Sites/homelab/proxmox validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Plan (owner's terminal)**

Run in the owner's Terminal panel: `op run --env-file=.env.op -- tofu plan -out=/tmp/vm.tfplan` from `proxmox/`.
Expected: `Plan: 4 to add, 0 to change, 0 to destroy.` (2 downloads, 2 VMs). A `403` here or in Task 7 names a privilege to add in Task 7 Step 1.

- [ ] **Step 5: Commit**

```bash
git add proxmox/
git commit -m "feat(proxmox): VM module booting the weekly homelab images"
```

---

### Task 7: Node one-off steps, proving on venus, docs, cleanup

**Files:**
- Modify: `proxmox/README.md` (role privileges; `import` content on `local`; "Virtual machines" and "Images" sections; `images_release` bump; schedule caveat; agent/terminal note)
- Modify: `README.md`, `CLAUDE.md` (one line each: `images/` and the workflow; `proxmox/` now does VMs too)
- Modify: `proxmox/vms.tf`, `proxmox/outputs.tf` (remove the test VMs at the end)

- [ ] **Step 1: Node one-off steps (builder's shell, root@172.16.16.91)**

`pvesm set local --content vztmpl,images,backup,iso,import`; `pveum role modify OpenTofu -privs "<current list> VM.Config.CDROM VM.Config.Cloudinit VM.Config.HWType"`. Verify: `pvesm status` shows `local` active; `pveum role list` shows the new privileges.

- [ ] **Step 2: Apply (owner's terminal)**

`op run --env-file=.env.op -- tofu apply /tmp/vm.tfplan`. Expected: `Apply complete! Resources: 4 added` and `vms` output with two addresses. On `403`, add the named privilege to the role and the README, re-plan, re-apply.

- [ ] **Step 3: Verify on the node**

Run: `ssh root@172.16.16.91 'qm list | grep -E "9101|9102"; qm agent 9101 network-get-interfaces | grep -m1 ip-address; qm agent 9102 network-get-interfaces | grep -m1 ip-address; qm config 9101 | grep -E "^(agent|ide2|scsi0|cicustom)"'`
Expected: both running; both report an RFC1918 address; `agent: 1`, `ide2: ...cloudinit`, no `cicustom` line.

- [ ] **Step 4: Verify in the guests (owner's terminal)**

For each address: `ssh -o StrictHostKeyChecking=accept-new root@<ip> 'hostname; test -f /var/lib/homelab/firstboot-done && echo firstboot-done; docker run --rm hello-world | head -2'`. Debian: `systemctl is-enabled unattended-upgrades`. Alpine: `ls -l /etc/periodic/daily/homelab-upgrade; rc-status | grep -E "podman|qemu-guest-agent"`. Then a one-service compose check: `printf 'services:\n  web:\n    image: docker.io/library/nginx:alpine\n' > /tmp/compose.yaml && podman-compose -f /tmp/compose.yaml up -d && podman ps && podman-compose -f /tmp/compose.yaml down`.
Expected: all succeed on both; the firstboot marker may take a few minutes to appear while the upgrade runs.

- [ ] **Step 5: Documentation**

`proxmox/README.md`: extend the role command and the one-off steps; a "Virtual machines" section modelled on "Adding a container" with a `module "example"` block (`image_file_id = proxmox_download_file.debian_vm.id`), what the images contain, where the address comes from (`tofu output vms`), and "Bumping the image" (`images_release`, affects new VMs only, never deletes the pinned release); an "Images" section pointing at `images/` and the weekly workflow, the pre-release behaviour, the 60-day schedule pause. Root `README.md` table and `CLAUDE.md` layout line gain `images/` and mention VMs.

- [ ] **Step 6: Remove the test VMs and apply (owner's terminal)**

Delete `local.test_vms`/`module "test_vm"` from `vms.tf` and the `vms` output (leave a commented example like `outputs.tf` has for containers). `tofu plan`: `0 to add, 0 to change, 2 to destroy`; apply; `ssh root@172.16.16.91 qm list` shows neither; `tofu state list` shows the two downloads and the LXC template only; `ssh-keygen -R <ip>` for both addresses.

- [ ] **Step 7: Format, validate, commit**

Run: `tofu -chdir=proxmox fmt -check -recursive && tofu -chdir=proxmox validate`; Expected: valid.

```bash
git add proxmox/ README.md CLAUDE.md
git commit -m "docs(proxmox): virtual machines, images and the node steps they need"
```

Squash this commit's `vms.tf`/`outputs.tf` edits into the Task 6 commit if the owner prefers a two-commit branch (images, tofu); otherwise leave as is.

- [ ] **Step 8: Show the owner**

`git log --oneline master..HEAD` and `git diff --stat claude/epic-wozniak-7uqv8r..HEAD`. Ask before pushing again or opening the draft PR. When the PR is opened, run the `project-manager` agent in check-only mode as the hook asks.
