#!/usr/bin/env bash
#
# Runs as root inside the Debian 13 image via `virt-customize --run`.
# Upgrades the image, installs the guest agent, Podman and unattended-upgrades,
# and enables their services plus homelab-firstboot. The apt, sshd, cloud-init
# and systemd files are copied in by images/build.sh before this runs, so this
# script only installs and enables.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y dist-upgrade
apt-get -y install qemu-guest-agent podman podman-docker podman-compose unattended-upgrades
systemctl enable qemu-guest-agent podman.socket homelab-firstboot unattended-upgrades
mkdir -p /var/lib/homelab
apt-get clean
