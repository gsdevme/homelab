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
#   resolve_alpine <listing_html>
#       Prints the URL of the newest Alpine 3.23 x86_64 bios-cloudinit qcow2
#       (highest point release, then highest -rN) in the releases/cloud index
#       and, on a second line, the URL of its .sha512 file, whose first field
#       is the sum. Only exact href file names count, so uefi, metal, other
#       arch and prefixed variants never win. Returns 1 if none is listed.
#
#   fetch_verified <url> <sha512> <dest>
#       Downloads <url> to <dest> and checks it against <sha512>. Returns
#       non-zero on a download failure or checksum mismatch.
#
#   output_name <debian|alpine> <tag>
#       Prints the file name of the built image for that distribution and tag.
#
#   select_prunable <keep_releases> <keep_prereleases> <pinned_tag>
#       Reads `gh release list --json tagName,isPrerelease,createdAt` JSON on
#       stdin and prints, one per line in ascending tag order, the images-
#       release tags to delete: everything but the newest <keep_releases>
#       releases and the newest <keep_prereleases> pre-releases, and never
#       <pinned_tag>. Newest is by createdAt, not by tag string, so branch
#       pre-releases built on the same day (images-YYYYMMDD-<sha7>) rank by
#       age rather than by commit hash. Tags not starting with images- are
#       never printed. Needs jq.

DEBIAN_BASE_URL="https://cloud.debian.org/images/cloud/trixie/latest/"
DEBIAN_IMAGE="debian-13-genericcloud-amd64.qcow2"
ALPINE_BASE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/"

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

resolve_alpine() {
  local listing=$1 image
  image=$(grep -o 'href="alpine-3\.23\.[0-9]*-x86_64-bios-cloudinit-r[0-9]*\.qcow2"' "$listing" \
    | sed 's/^href="//; s/"$//' | sort -uV | tail -1 || true)
  if [[ -z "$image" ]]; then
    echo "no 3.23 bios cloudinit x86_64 qcow2 in listing" >&2
    return 1
  fi
  printf '%s%s\n%s%s.sha512\n' "$ALPINE_BASE_URL" "$image" "$ALPINE_BASE_URL" "$image"
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

select_prunable() {
  local keep_releases=$1 keep_prereleases=$2 pinned=$3
  jq -r --argjson keep_rel "$keep_releases" --argjson keep_pre "$keep_prereleases" --arg pinned "$pinned" '
    def stale(pre; keep):
      map(select(.isPrerelease == pre)) | sort_by([.createdAt, .tagName]) | reverse | .[keep:];
    map(select(.tagName | startswith("images-")))
    | (stale(false; $keep_rel) + stale(true; $keep_pre))
    | map(.tagName | select(. != $pinned))
    | sort
    | .[]
  '
}
