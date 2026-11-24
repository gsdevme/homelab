#!/usr/bin/env bash
#
# Unit tests for images/lib.sh. No network: every input is a fixture file
# under images/tests/fixtures/, and downloads use file:// URLs.
#
# Usage: bash images/tests/test_lib.sh
# Prints one line per failure and a pass/fail summary; exits non-zero if any
# test fails.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=SCRIPTDIR/../lib.sh
source ../lib.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0
current=""

fail() {
  echo "FAIL ${current}: $1" >&2
  failures=$((failures + 1))
}

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

test_resolve_alpine_picks_newest_bios_cloudinit() {
  out=$(resolve_alpine fixtures/alpine-listing.html)
  [[ "$(sed -n 1p <<<"$out")" == "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/alpine-3.23.8-x86_64-bios-cloudinit-r0.qcow2" ]] || fail "url"
  [[ "$(sed -n 2p <<<"$out")" == "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/alpine-3.23.8-x86_64-bios-cloudinit-r0.qcow2.sha512" ]] || fail "sha url"
}

test_resolve_alpine_ignores_uefi_metal_and_other_arch() {
  out=$(resolve_alpine fixtures/alpine-listing.html)
  [[ "$(sed -n 1p <<<"$out")" == "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/alpine-3.23.8-x86_64-bios-cloudinit-r0.qcow2" ]] || fail "url"
  [[ "$out" != *uefi* ]] || fail "picked uefi"
  [[ "$out" != *metal* ]] || fail "picked metal"
  [[ "$out" != *aarch64* ]] || fail "picked aarch64"
}

test_resolve_alpine_fails_without_match() {
  ! resolve_alpine fixtures/empty.html 2>/dev/null || fail "should exit non-zero"
}

test_select_prunable_keeps_latest_and_pinned() {
  out=$(select_prunable 8 2 images-20260102 <fixtures/releases.json)
  [[ "$out" == $'images-20260101\nimages-20260201\nimages-20260202' ]] || fail "expected the oldest release and two oldest pre-releases, got: ${out}"
}

test_select_prunable_prunes_old_prereleases() {
  out=$(select_prunable 8 1 images-20260110 <fixtures/releases.json)
  [[ "$out" == $'images-20260101\nimages-20260102\nimages-20260201\nimages-20260202\nimages-20260203' ]] || fail "expected two releases and three pre-releases, got: ${out}"
}

test_select_prunable_ignores_foreign_tags() {
  out=$(select_prunable 0 0 images-20260110 <fixtures/releases.json)
  ! grep -qx v1.2.3 <<<"$out" || fail "foreign tag v1.2.3 selected"
  ! grep -qx images-20260110 <<<"$out" || fail "pinned tag selected"
  [[ "$(wc -l <<<"$out" | tr -d ' ')" == 13 ]] || fail "expected the 13 unpinned images- tags, got: ${out}"
}

test_select_prunable_treats_suffixed_tag_as_newest_prerelease() {
  out=$(select_prunable 10 1 images-20260110 <fixtures/releases.json)
  ! grep -qx images-20260203-abc1234 <<<"$out" || fail "newest pre-release images-20260203-abc1234 selected"
  grep -qx images-20260203 <<<"$out" || fail "images-20260203 should sort below its suffixed sibling"
  out=$(select_prunable 0 4 images-20260110 <fixtures/releases.json)
  ! grep -qx images-20260203-abc1234 <<<"$out" || fail "suffixed tag counted as a release, not a pre-release"
}

tests=(
  test_resolve_debian_finds_qcow2_and_sum
  test_resolve_debian_fails_without_match
  test_output_name
  test_fetch_verified_rejects_bad_sum
  test_resolve_alpine_picks_newest_bios_cloudinit
  test_resolve_alpine_ignores_uefi_metal_and_other_arch
  test_resolve_alpine_fails_without_match
  test_select_prunable_keeps_latest_and_pinned
  test_select_prunable_prunes_old_prereleases
  test_select_prunable_ignores_foreign_tags
  test_select_prunable_treats_suffixed_tag_as_newest_prerelease
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
