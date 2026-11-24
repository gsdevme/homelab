#!/usr/bin/env bash
#
# Dry structural tests for images/check.sh. libguestfs is not needed: virt-ls
# and virt-cat are replaced by shell functions that read a fixture directory
# tree standing in for the guest filesystem, whose path is passed where the
# image would be. Each check runs in a child bash that sources check.sh and
# the stubs, so check.sh's own set -e applies just as in CI (a function run
# under `if` here would have it suspended).
#
# Each test builds a fresh tree with make_debian or make_alpine, a correct
# image as images/build.sh and the customize scripts leave it, with the
# copied-in files taken from the real sources under images/. A test may then
# break one thing and expect the matching check to fail. Ownership defaults to
# 0:0; a line "<path> <uid> <gid>" in the tree's .owners file overrides it.
# The long listing reports mode 0755 for executable fixture files and
# directories, 0644 otherwise, and type l with " -> <target>" for symlinks. A guest path listed in the tree's .broken file
# makes virt-ls (for a directory) or virt-cat (for a file) fail, as a
# libguestfs error would.
#
# Usage: bash images/tests/test_check.sh
# Prints one line per failure and a pass/fail summary; exits non-zero if any
# test fails.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
images=$(dirname "$here")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0
current=""
root=""

fail() {
  echo "FAIL ${current}: $1" >&2
  failures=$((failures + 1))
}

#######################################
# Stand-in for virt-ls. Supports `-a <tree> <dir>` (names, one per line) and
# `-lR --uids -a <tree> <dir>` (one "<type> <mode> <size> <uid> <gid> <path>"
# line per entry below dir, as libguestfs prints it).
#######################################
virt-ls() {
  local long=0 tree="" dir
  while (($# > 1)); do
    case "$1" in
      -lR) long=1 ;;
      --uids) ;;
      -a) tree=$2; shift ;;
      *) return 2 ;;
    esac
    shift
  done
  dir=$1
  if [[ ! -d "$tree$dir" ]] || grep -qxF -- "$dir" "$tree/.broken"; then
    echo "virt-ls: $dir: cannot list" >&2
    return 1
  fi
  if ((long == 0)); then
    ls -A "$tree$dir"
    return
  fi
  local entry path owner type mode link
  while IFS= read -r entry; do
    path=${entry#"$tree"}
    owner=$(awk -v p="$path" '$1 == p {print $2, $3}' "$tree/.owners")
    type=-
    mode=0644
    link=""
    [[ -d "$entry" ]] && type=d
    [[ -x "$entry" ]] && mode=0755
    if [[ -L "$entry" ]]; then
      type=l
      mode=0777
      link=" -> $(readlink "$entry")"
    fi
    echo "$type $mode 0 ${owner:-0 0} $path$link"
  done < <(find "$tree$dir" -mindepth 1)
}

#######################################
# Stand-in for virt-cat: `-a <tree> <path>`.
#######################################
virt-cat() {
  [[ "$1" == -a ]] || return 2
  if grep -qxF -- "$3" "$2/.broken"; then
    echo "virt-cat: $3: cannot read" >&2
    return 1
  fi
  cat "$2$3"
}

put() {
  mkdir -p "$(dirname "$root$1")"
  if (($# > 1)); then
    printf '%s\n' "$2" > "$root$1"
  else
    : > "$root$1"
  fi
}

copy() {
  mkdir -p "$(dirname "$root$2")"
  cp "$images/$1" "$root$2"
}

make_common() {
  root="$tmp/$current"
  rm -rf "$root"
  mkdir -p "$root/var/lib/homelab" "$root/etc/ssh"
  : > "$root/.owners"
  : > "$root/.broken"
  put /etc/ssh/sshd_config "Include /etc/ssh/sshd_config.d/*.conf"
  copy common/10-homelab-root.conf /etc/ssh/sshd_config.d/10-homelab-root.conf
  copy common/90-homelab.cfg /etc/cloud/cloud.cfg.d/90-homelab.cfg
}

link() {
  mkdir -p "$(dirname "$root$1")"
  ln -s "$2" "$root$1"
}

make_debian() {
  make_common
  put /etc/machine-id
  local pkg
  for pkg in qemu-guest-agent podman podman-docker podman-compose unattended-upgrades; do
    put "/var/lib/dpkg/info/$pkg.list" "/."
  done
  copy debian/50unattended-upgrades-homelab /etc/apt/apt.conf.d/50unattended-upgrades-homelab
  copy debian/20auto-upgrades-homelab /etc/apt/apt.conf.d/20auto-upgrades-homelab
  copy debian/homelab-firstboot.service /etc/systemd/system/homelab-firstboot.service
  copy debian/homelab-firstboot.sh /usr/local/sbin/homelab-firstboot
  chmod 755 "$root/usr/local/sbin/homelab-firstboot"
  link /etc/systemd/system/cloud-init.target.wants/homelab-firstboot.service /etc/systemd/system/homelab-firstboot.service
  link /etc/systemd/system/sockets.target.wants/podman.socket /usr/lib/systemd/system/podman.socket
  link /etc/systemd/system/multi-user.target.wants/unattended-upgrades.service /usr/lib/systemd/system/unattended-upgrades.service
  link /etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service /usr/lib/systemd/system/qemu-guest-agent.service
  put /usr/lib/systemd/system/qemu-guest-agent.service $'[Unit]\nDescription=QEMU Guest Agent\n\n[Install]\nWantedBy=multi-user.target'
}

make_alpine() {
  make_common
  put /etc/apk/world $'alpine-base\nip6tables\niptables\nopenssh\npodman\npodman-compose\npodman-docker\nqemu-guest-agent'
  put /etc/rc.conf $'rc_parallel="NO"\nrc_cgroup_mode="unified"'
  put /etc/containers/registries.conf 'unqualified-search-registries = ["docker.io"]'
  copy alpine/homelab-firstboot /etc/init.d/homelab-firstboot
  copy alpine/homelab-upgrade.cron /etc/periodic/daily/homelab-upgrade
  chmod 755 "$root/etc/init.d/homelab-firstboot" "$root/etc/periodic/daily/homelab-upgrade"
  local svc
  for svc in qemu-guest-agent podman crond homelab-firstboot; do
    put "/etc/runlevels/default/$svc"
  done
  put /etc/runlevels/sysinit/cgroups
}

#######################################
# Runs check function $1 from images/check.sh against the current tree in a
# child bash, with the virt-ls and virt-cat stubs defined.
#######################################
run_check() {
  bash -c "$(declare -f virt-ls virt-cat)"'
    source "$1"
    img=$2
    "$3"' _ "$images/check.sh" "$root" "$1" 2>&1
}

expect_pass() {
  local out
  if ! out=$(run_check "$1"); then
    fail "expected pass, got: $(grep FAIL <<<"$out")"
  fi
}

expect_fail() {
  local out
  if out=$(run_check "$1"); then
    fail "expected failure mentioning '$2'"
  elif ! grep -qF -- "FAIL: " <<<"$out" || ! grep -F -- "FAIL: " <<<"$out" | grep -qF -- "$2"; then
    fail "failed for the wrong reason: $(grep FAIL <<<"$out")"
  fi
}

test_debian_passes() {
  make_debian
  expect_pass check_debian
}

test_alpine_passes() {
  make_alpine
  expect_pass check_alpine
}

test_debian_fails_when_firstboot_done() {
  make_debian
  put /var/lib/homelab/firstboot-done
  expect_fail check_debian firstboot-done
}

test_debian_fails_without_firstboot_wants() {
  make_debian
  rm "$root/etc/systemd/system/cloud-init.target.wants/homelab-firstboot.service"
  expect_fail check_debian cloud-init.target.wants/homelab-firstboot.service
}

test_debian_fails_without_package() {
  make_debian
  rm "$root/var/lib/dpkg/info/podman-compose.list"
  expect_fail check_debian podman-compose
}

test_debian_fails_without_clear_line() {
  make_debian
  sed -i.bak '/#clear/d' "$root/etc/apt/apt.conf.d/50unattended-upgrades-homelab"
  expect_fail check_debian '#clear Unattended-Upgrade::Origins-Pattern;'
}

test_debian_fails_when_copied_file_not_root() {
  make_debian
  echo "/usr/local/sbin/homelab-firstboot 1000 1000" >> "$root/.owners"
  expect_fail check_debian /usr/local/sbin/homelab-firstboot
}

test_debian_accepts_static_guest_agent() {
  make_debian
  rm "$root/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service"
  put /usr/lib/systemd/system/qemu-guest-agent.service $'[Unit]\nDescription=QEMU Guest Agent\n\n[Service]\nExecStart=/usr/sbin/qemu-ga'
  expect_pass check_debian
}

test_debian_accepts_empty_install_section() {
  make_debian
  rm "$root/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service"
  put /usr/lib/systemd/system/qemu-guest-agent.service $'[Unit]\nDescription=QEMU Guest Agent\n\n[Service]\nExecStart=-/usr/sbin/qemu-ga\n\n[Install]'
  expect_pass check_debian
}

test_debian_fails_with_unlinked_installable_guest_agent() {
  make_debian
  rm "$root/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service"
  expect_fail check_debian qemu-guest-agent
}

test_debian_fails_with_machine_id() {
  make_debian
  put /etc/machine-id 0123456789abcdef0123456789abcdef
  expect_fail check_debian /etc/machine-id
}

test_debian_fails_with_ssh_host_key() {
  make_debian
  put /etc/ssh/ssh_host_ed25519_key
  expect_fail check_debian ssh_host_
}

test_alpine_fails_without_cgroups() {
  make_alpine
  rm "$root/etc/runlevels/sysinit/cgroups"
  expect_fail check_alpine cgroups
}

test_alpine_accepts_cgroups_in_default() {
  make_alpine
  rm "$root/etc/runlevels/sysinit/cgroups"
  put /etc/runlevels/default/cgroups
  expect_pass check_alpine
}

test_alpine_fails_without_runlevel_link() {
  make_alpine
  rm "$root/etc/runlevels/default/homelab-firstboot"
  expect_fail check_alpine runlevels/default/homelab-firstboot
}

test_alpine_fails_without_world_entry() {
  make_alpine
  sed -i.bak '/^podman-docker$/d' "$root/etc/apk/world"
  expect_fail check_alpine podman-docker
}

test_alpine_fails_without_cgroup_mode() {
  make_alpine
  put /etc/rc.conf 'rc_parallel="NO"'
  expect_fail check_alpine rc_cgroup_mode
}

test_alpine_fails_without_common_file() {
  make_alpine
  rm "$root/etc/cloud/cloud.cfg.d/90-homelab.cfg"
  expect_fail check_alpine 90-homelab.cfg
}

test_alpine_fails_when_upgrade_job_not_root() {
  make_alpine
  echo "/etc/periodic/daily/homelab-upgrade 501 20" >> "$root/.owners"
  expect_fail check_alpine /etc/periodic/daily/homelab-upgrade
}

test_alpine_fails_when_firstboot_done() {
  make_alpine
  put /var/lib/homelab/firstboot-done
  expect_fail check_alpine firstboot-done
}

test_debian_fails_when_firstboot_dir_unlistable() {
  make_debian
  echo /var/lib/homelab >> "$root/.broken"
  expect_fail check_debian "/var/lib/homelab cannot be listed"
}

test_debian_fails_when_etc_unlistable() {
  make_debian
  echo /etc >> "$root/.broken"
  expect_fail check_debian "/etc cannot be listed"
}

test_debian_fails_when_static_unit_unreadable() {
  make_debian
  rm "$root/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service"
  put /usr/lib/systemd/system/qemu-guest-agent.service $'[Unit]\nDescription=QEMU Guest Agent'
  echo /usr/lib/systemd/system/qemu-guest-agent.service >> "$root/.broken"
  expect_fail check_debian "qemu-guest-agent.service cannot be read"
}

test_debian_fails_when_firstboot_not_executable() {
  make_debian
  chmod 644 "$root/usr/local/sbin/homelab-firstboot"
  expect_fail check_debian "/usr/local/sbin/homelab-firstboot has mode '0644'"
}

test_alpine_fails_when_upgrade_job_not_executable() {
  make_alpine
  chmod 644 "$root/etc/periodic/daily/homelab-upgrade"
  expect_fail check_alpine "/etc/periodic/daily/homelab-upgrade has mode '0644'"
}

test_alpine_fails_when_marker_dir_unlistable() {
  make_alpine
  echo /var/lib/homelab >> "$root/.broken"
  expect_fail check_alpine "/var/lib/homelab cannot be listed"
}

tests=(
  test_debian_passes
  test_alpine_passes
  test_debian_fails_when_firstboot_done
  test_debian_fails_without_firstboot_wants
  test_debian_fails_without_package
  test_debian_fails_without_clear_line
  test_debian_fails_when_copied_file_not_root
  test_debian_accepts_static_guest_agent
  test_debian_accepts_empty_install_section
  test_debian_fails_with_unlinked_installable_guest_agent
  test_debian_fails_with_machine_id
  test_debian_fails_with_ssh_host_key
  test_alpine_fails_without_cgroups
  test_alpine_accepts_cgroups_in_default
  test_alpine_fails_without_runlevel_link
  test_alpine_fails_without_world_entry
  test_alpine_fails_without_cgroup_mode
  test_alpine_fails_without_common_file
  test_alpine_fails_when_upgrade_job_not_root
  test_alpine_fails_when_firstboot_done
  test_debian_fails_when_firstboot_dir_unlistable
  test_debian_fails_when_etc_unlistable
  test_debian_fails_when_static_unit_unreadable
  test_debian_fails_when_firstboot_not_executable
  test_alpine_fails_when_upgrade_job_not_executable
  test_alpine_fails_when_marker_dir_unlistable
)

passed=0
for current in "${tests[@]}"; do
  before=$failures
  "$current"
  if ((failures == before)); then
    passed=$((passed + 1))
  fi
done

echo "${passed} passed, $((${#tests[@]} - passed)) failed"
((failures == 0))
