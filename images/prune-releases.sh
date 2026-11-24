#!/usr/bin/env bash
#
# Prunes old homelab image releases from GitHub.
#
# Usage: images/prune-releases.sh [--dry-run] <keep_releases> <keep_prereleases>
#
# Keeps the newest <keep_releases> images-YYYYMMDD releases, the newest
# <keep_prereleases> pre-releases, and the release proxmox/variables.tf pins in
# images_release (so the image the Proxmox module boots is never deleted).
# Every other images- release is deleted together with its tag; releases with
# other tags are left alone. Selection is select_prunable in lib.sh.
#
# Prints "keep: <tag>" and "delete: <tag>" per images- release. With --dry-run
# it only prints. Needs gh (authenticated, GH_TOKEN in CI) and jq. Exits
# non-zero if the pin cannot be read, so nothing is pruned without it.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=SCRIPTDIR/lib.sh
source "$here/lib.sh"

usage() {
  echo "usage: $0 [--dry-run] <keep_releases> <keep_prereleases>" >&2
  exit 2
}

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi
[[ $# -eq 2 && "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] || usage

pinned=$(grep -o 'default *= *"images-[0-9]\{8\}\(-[0-9a-f]\{7\}\)\?"' "$here/../proxmox/variables.tf" \
  | grep -o 'images-[0-9a-f-]*' | head -1 || true)
if [[ -z "$pinned" ]]; then
  echo "no images_release pin found in proxmox/variables.tf" >&2
  exit 1
fi

releases=$(gh release list --limit 200 --json tagName,isPrerelease,createdAt)
prunable=$(select_prunable "$1" "$2" "$pinned" <<<"$releases")

while read -r tag; do
  grep -qxF "$tag" <<<"$prunable" || echo "keep: ${tag}"
done < <(jq -r '.[].tagName | select(startswith("images-"))' <<<"$releases" | sort)

while read -r tag; do
  [[ -n "$tag" ]] || continue
  echo "delete: ${tag}"
  if ! $dry_run; then
    gh release delete "$tag" --cleanup-tag --yes
  fi
done <<<"$prunable"
