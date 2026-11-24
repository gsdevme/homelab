#!/usr/bin/env bash
#
# Checks the content of a built homelab Proxmox VM image.
#
# Usage: images/check.sh <debian|alpine> <image>
#
# Runs after images/build.sh against the output qcow2 and asserts, read-only
# with virt-ls and virt-cat (libguestfs-tools, so Linux only), that the image
# carries what build.sh and the customize scripts put in it: the packages, the
# copied-in files with their key lines and root:root ownership, the enabled
# services, the sysprep result (no machine-id, no SSH host keys, first-boot
# marker not yet written). Prints "ok: <what>" per passing assertion and stops
# at the first failure with "FAIL: <what>" and exit status 1.
#
# Sourcing the file defines the helpers and check functions without running
# them; tests set img and replace virt-ls and virt-cat with shell functions.
#
# The predicates (present, contains, absent, ...) are mostly run through
# verdict, which shellcheck cannot follow, hence the SC2329 exemption.
# shellcheck disable=SC2329
set -euo pipefail

img=""

debian_packages=(qemu-guest-agent podman podman-docker podman-compose unattended-upgrades)
alpine_packages=(qemu-guest-agent podman podman-docker podman-compose iptables ip6tables)

debian_copied=(
  /etc/apt/apt.conf.d/50unattended-upgrades-homelab
  /etc/apt/apt.conf.d/20auto-upgrades-homelab
  /etc/systemd/system/homelab-firstboot.service
  /etc/ssh/sshd_config.d/10-homelab-root.conf
  /etc/cloud/cloud.cfg.d/90-homelab.cfg
)
alpine_copied=(
  /etc/ssh/sshd_config.d/10-homelab-root.conf
  /etc/cloud/cloud.cfg.d/90-homelab.cfg
)

debian_executables=(/usr/local/sbin/homelab-firstboot)
alpine_executables=(/etc/init.d/homelab-firstboot /etc/periodic/daily/homelab-upgrade)

usage() {
  echo "usage: $0 <debian|alpine> <image>" >&2
  exit 2
}

ok() {
  echo "ok: $1"
}

die() {
  echo "FAIL: $1" >&2
  exit 1
}

#######################################
# Runs the command after the first two arguments; prints ok with message $1
# if it succeeds, otherwise fails with message $2.
#######################################
verdict() {
  local pass=$1 failure=$2
  shift 2
  if "$@"; then
    ok "$pass"
  else
    die "$failure"
  fi
}

#######################################
# Predicates: return 0 or 1 without printing. Output is captured before it is
# searched so that grep -q closing the pipe early cannot fail the pipeline.
# The positive ones (present, contains, has_line) return 1 when virt-ls or
# virt-cat fails; the negative ones (absent, not_installable) die instead, so
# a tool failure can never read as "not there".
#######################################
present() {
  local listing
  listing=$(virt-ls -a "$img" "$(dirname "$1")" 2>/dev/null) || return 1
  grep -qxF -- "$(basename "$1")" <<<"$listing"
}

contains() {
  local content
  present "$1" || return 1
  content=$(virt-cat -a "$img" "$1") || return 1
  grep -qF -- "$2" <<<"$content"
}

has_line() {
  local content
  present "$1" || return 1
  content=$(virt-cat -a "$img" "$1") || return 1
  grep -qxF -- "$2" <<<"$content"
}

absent() {
  local listing
  listing=$(virt-ls -a "$img" "$(dirname "$1")") || die "$(dirname "$1") cannot be listed"
  ! grep -qxF -- "$(basename "$1")" <<<"$listing"
}

#######################################
# Returns 0 if unit file $1 has no install target: no WantedBy=, RequiredBy=,
# UpheldBy= or Alias= line, so systemctl enable has nothing to link. Debian's
# qemu-guest-agent.service is like this, with an empty [Install] section.
# Dies if the unit cannot be read.
#######################################
not_installable() {
  local content
  content=$(virt-cat -a "$img" "$1") || die "$1 cannot be read"
  ! grep -qE '^[[:space:]]*(WantedBy|RequiredBy|UpheldBy|Alias)[[:space:]]*=' <<<"$content"
}

empty() {
  [[ -z "$1" ]]
}

#######################################
# Assertions: print ok or FAIL, and exit on FAIL.
#######################################
has_file() {
  verdict "$1 exists" "$1 is missing" present "$1"
}

no_file() {
  verdict "$1 is absent" "$1 should not exist" absent "$1"
}

file_contains() {
  verdict "$1 contains '$2'" "$1 does not contain '$2'" contains "$1" "$2"
}

file_has_line() {
  verdict "$1 has line '$2'" "$1 has no line '$2'" has_line "$1" "$2"
}

file_absent_or_empty() {
  local content=""
  if ! absent "$1"; then
    content=$(virt-cat -a "$img" "$1") || die "$1 cannot be read"
  fi
  verdict "$1 is absent or empty" "$1 is not empty" empty "$content"
}

#######################################
# Asserts no entry of directory $1 starts with $2.
#######################################
no_file_matching() {
  local listing
  listing=$(virt-ls -a "$img" "$1") || die "$1 cannot be listed"
  verdict "no $1/$2*" "$1 holds $2* files" empty "$(grep -- "^$2" <<<"$listing" || true)"
}

#######################################
# Asserts $1 is owned by uid 0 and gid 0 and, when $2 is given, has octal
# mode $2. Both come from one virt-ls -lR --uids of its directory, whose lines
# read "<type> <mode> <size> <uid> <gid> <path>", with " -> <target>" appended
# for symlinks. The entry is matched on its own path (field 6) and symlink
# lines are skipped, so a link that targets $1 is never mistaken for it. Paths
# containing spaces are not supported.
#######################################
owned_by_root() {
  local listing entry owner mode
  listing=$(virt-ls -lR --uids -a "$img" "$(dirname "$1")") || die "$(dirname "$1") cannot be listed"
  entry=$(awk -v p="$1" '$1 != "l" && $6 == p' <<<"$listing")
  owner=$(awk '{print $4 ":" $5}' <<<"$entry")
  verdict "$1 is owned by root:root" "$1 is owned by '${owner:-unknown}', not root:root" test "$owner" = "0:0"
  if (($# > 1)); then
    mode=$(awk '{print $2}' <<<"$entry")
    verdict "$1 has mode $2" "$1 has mode '${mode:-unknown}', not $2" test "$mode" = "$2"
  fi
}

#######################################
# Asserts service link $2 is present in the systemd wants or OpenRC runlevel
# directory $1.
#######################################
wants() {
  verdict "$1/$2 is linked" "$1/$2 is not linked" present "$1/$2"
}

#######################################
# Asserts the guest agent is enabled on Debian: either linked into
# multi-user.target.wants, or shipped as a static unit (no install target, see
# not_installable) that its udev rule starts.
#######################################
guest_agent_enabled() {
  local link=/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service unit
  if present "$link"; then
    ok "$link is linked"
    return
  fi
  for unit in /usr/lib/systemd/system/qemu-guest-agent.service /lib/systemd/system/qemu-guest-agent.service; do
    if present "$unit"; then
      verdict "$unit is static" "$unit is installable but $link is not linked" not_installable "$unit"
      return
    fi
  done
  die "qemu-guest-agent.service is neither linked nor installed"
}

check_common() {
  file_absent_or_empty /etc/machine-id
  no_file_matching /etc/ssh ssh_host_
  file_contains /etc/ssh/sshd_config.d/10-homelab-root.conf "PermitRootLogin prohibit-password"
  file_contains /etc/cloud/cloud.cfg.d/90-homelab.cfg "disable_root: false"
  has_file /var/lib/homelab
  no_file /var/lib/homelab/firstboot-done
}

check_debian() {
  local pkg path
  check_common
  for pkg in "${debian_packages[@]}"; do
    has_file "/var/lib/dpkg/info/$pkg.list"
  done
  for path in "${debian_copied[@]}"; do
    has_file "$path"
    owned_by_root "$path"
  done
  for path in "${debian_executables[@]}"; do
    has_file "$path"
    owned_by_root "$path" 0755
  done
  file_contains /etc/apt/apt.conf.d/50unattended-upgrades-homelab "#clear Unattended-Upgrade::Origins-Pattern;"
  # shellcheck disable=SC2016
  file_contains /etc/apt/apt.conf.d/50unattended-upgrades-homelab 'origin=Debian,codename=${distro_codename}-security'
  file_contains /etc/apt/apt.conf.d/50unattended-upgrades-homelab 'Unattended-Upgrade::Automatic-Reboot "false"'
  file_contains /etc/apt/apt.conf.d/20auto-upgrades-homelab 'APT::Periodic::Update-Package-Lists "1"'
  file_contains /etc/apt/apt.conf.d/20auto-upgrades-homelab 'APT::Periodic::Unattended-Upgrade "1"'
  file_contains /etc/systemd/system/homelab-firstboot.service "ExecStart=/usr/local/sbin/homelab-firstboot"
  file_contains /etc/systemd/system/homelab-firstboot.service "ConditionPathExists=!/var/lib/homelab/firstboot-done"
  file_contains /etc/systemd/system/homelab-firstboot.service "WantedBy=cloud-init.target"
  file_contains /usr/local/sbin/homelab-firstboot "touch /var/lib/homelab/firstboot-done"
  no_file /usr/local/sbin/homelab-firstboot.sh
  wants /etc/systemd/system/cloud-init.target.wants homelab-firstboot.service
  wants /etc/systemd/system/sockets.target.wants podman.socket
  wants /etc/systemd/system/multi-user.target.wants unattended-upgrades.service
  guest_agent_enabled
}

check_alpine() {
  local pkg path svc
  check_common
  for pkg in "${alpine_packages[@]}"; do
    file_has_line /etc/apk/world "$pkg"
  done
  for path in "${alpine_copied[@]}"; do
    has_file "$path"
    owned_by_root "$path"
  done
  for path in "${alpine_executables[@]}"; do
    has_file "$path"
    owned_by_root "$path" 0755
  done
  file_contains /etc/init.d/homelab-firstboot "marker=/var/lib/homelab/firstboot-done"
  file_contains /etc/periodic/daily/homelab-upgrade "apk upgrade --available"
  for svc in qemu-guest-agent podman crond homelab-firstboot; do
    wants /etc/runlevels/default "$svc"
  done
  if present /etc/runlevels/sysinit/cgroups; then
    ok "/etc/runlevels/sysinit/cgroups is linked"
  else
    wants /etc/runlevels/default cgroups
  fi
  file_contains /etc/rc.conf 'rc_cgroup_mode="unified"'
  file_contains /etc/containers/registries.conf 'unqualified-search-registries = ["docker.io"]'
  file_contains /etc/ssh/sshd_config "Include /etc/ssh/sshd_config.d/*.conf"
}

main() {
  [[ $# -eq 2 ]] || usage
  img=$2
  [[ -f "$img" ]] || die "$img is not a file"
  case "$1" in
    debian) check_debian ;;
    alpine) check_alpine ;;
    *) usage ;;
  esac
  echo "all checks passed for $1 image $img"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
