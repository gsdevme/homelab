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

tests=(
  test_resolve_debian_finds_qcow2_and_sum
  test_resolve_debian_fails_without_match
  test_output_name
  test_fetch_verified_rejects_bad_sum
  test_resolve_alpine_picks_newest_bios_cloudinit
  test_resolve_alpine_ignores_uefi_metal_and_other_arch
  test_resolve_alpine_fails_without_match
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
