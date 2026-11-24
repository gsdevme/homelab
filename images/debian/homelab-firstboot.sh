#!/usr/bin/env bash
#
# Installed as /usr/local/sbin/homelab-firstboot and run once by
# homelab-firstboot.service: brings a freshly cloned VM fully up to date, then
# writes the marker that stops the unit running again.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update && apt-get -y dist-upgrade && apt-get -y autoremove && touch /var/lib/homelab/firstboot-done
