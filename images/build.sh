#!/usr/bin/env bash
#
# Builds a homelab Proxmox VM image.
#
# Usage: images/build.sh <debian|alpine> <tag>
#
# The tag is images-YYYYMMDD when run from CI; locally anything will do.
# Writes images/build/<name>.qcow2 and images/build/<name>.qcow2.sha256, where
# <name> comes from output_name in lib.sh. Needs curl and libguestfs-tools
# (virt-customize, virt-sysprep, virt-sparsify), so it runs on Linux only.
#
# Debian: downloads the latest trixie genericcloud amd64 image, verifies it
# against the published SHA512SUMS, copies in the apt update policy, the
# first-boot upgrade unit and the shared sshd/cloud-init drop-ins (chowned to
# root, since --copy-in keeps the host uid), runs debian/customize.sh inside
# the guest, all on a work copy. The work copy is then sysprepped (without the
# customize operation, whose machine-id step would write a fresh ID straight
# after the machine-id operation empties the file) and sparsified
# with compression into the output image, which is checksummed.
#
# Alpine: downloads the newest 3.23 x86_64 bios-cloudinit image from the
# releases/cloud index, verifies it against its .sha512 file, copies in the
# first-boot OpenRC script, the daily upgrade job and the same shared drop-ins
# (chowned to root), runs alpine/customize.sh inside the guest, and finishes
# with the same work-copy sysprep, sparsify and checksum steps.
#
# The customize scripts download packages, so the libguestfs appliance needs
# its network: libguestfs brings it up with a DHCP client from the host and,
# for each --run or --run-command, swaps the appliance's /etc/resolv.conf into
# the guest and restores the guest's own afterwards.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/lib.sh
source "$here/lib.sh"

usage() {
  echo "usage: $0 <debian|alpine> <tag>" >&2
  exit 2
}

build_debian() {
  local work=$1 resolved url sum
  curl -fsSL --retry 3 -o "$build/debian-listing.html" "$DEBIAN_BASE_URL"
  curl -fsSL --retry 3 -o "$build/debian-SHA512SUMS" "${DEBIAN_BASE_URL}SHA512SUMS"
  resolved=$(resolve_debian "$build/debian-listing.html" "$build/debian-SHA512SUMS")
  url=$(sed -n 1p <<<"$resolved")
  sum=$(sed -n 2p <<<"$resolved")
  fetch_verified "$url" "$sum" "$build/upstream-debian.qcow2"
  cp "$build/upstream-debian.qcow2" "$work"

  virt-customize -a "$work" \
    --copy-in "$here/debian/50unattended-upgrades-homelab:/etc/apt/apt.conf.d" \
    --copy-in "$here/debian/20auto-upgrades-homelab:/etc/apt/apt.conf.d" \
    --copy-in "$here/debian/homelab-firstboot.service:/etc/systemd/system" \
    --copy-in "$here/debian/homelab-firstboot.sh:/usr/local/sbin" \
    --run-command 'mv /usr/local/sbin/homelab-firstboot.sh /usr/local/sbin/homelab-firstboot && chmod 755 /usr/local/sbin/homelab-firstboot' \
    --copy-in "$here/common/10-homelab-root.conf:/etc/ssh/sshd_config.d" \
    --copy-in "$here/common/90-homelab.cfg:/etc/cloud/cloud.cfg.d" \
    --run-command 'chown root:root /etc/apt/apt.conf.d/50unattended-upgrades-homelab /etc/apt/apt.conf.d/20auto-upgrades-homelab /etc/systemd/system/homelab-firstboot.service /usr/local/sbin/homelab-firstboot /etc/ssh/sshd_config.d/10-homelab-root.conf /etc/cloud/cloud.cfg.d/90-homelab.cfg' \
    --run "$here/debian/customize.sh"
}

build_alpine() {
  local work=$1 resolved url sum
  curl -fsSL --retry 3 -o "$build/alpine-listing.html" "$ALPINE_BASE_URL"
  resolved=$(resolve_alpine "$build/alpine-listing.html")
  url=$(sed -n 1p <<<"$resolved")
  sum=$(curl -fsSL --retry 3 "$(sed -n 2p <<<"$resolved")" | awk '{print $1}')
  fetch_verified "$url" "$sum" "$build/upstream-alpine.qcow2"
  cp "$build/upstream-alpine.qcow2" "$work"

  virt-customize -a "$work" \
    --copy-in "$here/alpine/homelab-firstboot:/etc/init.d" \
    --copy-in "$here/alpine/homelab-upgrade.cron:/tmp" \
    --run-command 'mv /tmp/homelab-upgrade.cron /etc/periodic/daily/homelab-upgrade' \
    --mkdir /etc/ssh/sshd_config.d \
    --copy-in "$here/common/10-homelab-root.conf:/etc/ssh/sshd_config.d" \
    --copy-in "$here/common/90-homelab.cfg:/etc/cloud/cloud.cfg.d" \
    --run-command 'chown root:root /etc/init.d/homelab-firstboot /etc/periodic/daily/homelab-upgrade /etc/ssh/sshd_config.d/10-homelab-root.conf /etc/cloud/cloud.cfg.d/90-homelab.cfg' \
    --run "$here/alpine/customize.sh"
}

[[ $# -eq 2 ]] || usage
distribution=$1
tag=$2
build="$here/build"
mkdir -p "$build"

case "$distribution" in
  debian)
    out="$build/$(output_name debian "$tag")"
    work="$build/work-debian.qcow2"
    build_debian "$work"
    ;;
  alpine)
    out="$build/$(output_name alpine "$tag")"
    work="$build/work-alpine.qcow2"
    build_alpine "$work"
    ;;
  *) usage ;;
esac

virt-sysprep --operations defaults,-customize -a "$work"
virt-sparsify --compress "$work" "$out"
rm -f "$work"
(cd "$build" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256")
