#!/usr/bin/env bash
#
# Shared functions for the homelab Proxmox VM image build. Sourced by
# images/build.sh and images/tests/test_lib.sh; defines functions only and has
# no side effects when sourced.
#
#   resolve_debian <listing_html> <sha512sums>
#       Prints the URL of the Debian 13 genericcloud amd64 qcow2 from the
#       trixie/latest index and, on a second line, its sha512 from SHA512SUMS.
#       Returns 1 if the listing has no such image or the sums lack its line.
#
#   fetch_verified <url> <sha512> <dest>
#       Downloads <url> to <dest> and checks it against <sha512>. Returns
#       non-zero on a download failure or checksum mismatch.
#
#   output_name <debian|alpine> <tag>
#       Prints the file name of the built image for that distribution and tag.

DEBIAN_BASE_URL="https://cloud.debian.org/images/cloud/trixie/latest/"
DEBIAN_IMAGE="debian-13-genericcloud-amd64.qcow2"

resolve_debian() {
  local listing=$1 sums=$2 sum
  if ! grep -qo "href=\"${DEBIAN_IMAGE}\"" "$listing"; then
    echo "no genericcloud amd64 qcow2 in listing" >&2
    return 1
  fi
  sum=$(awk -v f="$DEBIAN_IMAGE" '$2 == f {print $1}' "$sums")
  if [[ -z "$sum" ]]; then
    echo "no checksum for ${DEBIAN_IMAGE}" >&2
    return 1
  fi
  printf '%s%s\n%s\n' "$DEBIAN_BASE_URL" "$DEBIAN_IMAGE" "$sum"
}

fetch_verified() {
  local url=$1 sum=$2 dest=$3 actual
  curl -fsSL --retry 3 -o "$dest" "$url"
  actual=$(sha512sum "$dest" | awk '{print $1}')
  if [[ "$actual" != "$sum" ]]; then
    echo "sha512 mismatch for ${url}: expected ${sum}, got ${actual}" >&2
    return 1
  fi
}

output_name() {
  local distribution=$1 tag=$2
  case "$distribution" in
    debian) echo "debian-13-homelab-${tag}.qcow2" ;;
    alpine) echo "alpine-3.23-homelab-${tag}.qcow2" ;;
    *)
      echo "unknown distribution: ${distribution}" >&2
      return 1
      ;;
  esac
}
