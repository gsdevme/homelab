#!/bin/sh
#
# Runs as root inside the Alpine 3.23 image via `virt-customize --run`.
# Upgrades the image, installs the guest agent and Podman (plus iptables and
# ip6tables, which Podman's netavark backend needs and the podman package does
# not pull in), enables
# their OpenRC services plus cgroups, crond and homelab-firstboot, switches
# OpenRC to the unified cgroup v2 hierarchy Podman expects, makes bare image
# names resolve on docker.io, and makes sure sshd reads its drop-in directory.
# The OpenRC script, the daily upgrade job and the shared sshd/cloud-init
# drop-ins are copied in by images/build.sh before this runs.
set -eu

apk update
apk upgrade --available
apk add qemu-guest-agent podman podman-docker podman-compose iptables ip6tables

rc-update add qemu-guest-agent default
rc-update add podman default
rc-update add cgroups sysinit
rc-update add crond default
rc-update add homelab-firstboot default

if grep -q '^#\?rc_cgroup_mode=' /etc/rc.conf; then
  sed -i 's/^#\?rc_cgroup_mode=.*/rc_cgroup_mode="unified"/' /etc/rc.conf
else
  echo 'rc_cgroup_mode="unified"' >> /etc/rc.conf
fi

mkdir -p /etc/containers
echo 'unqualified-search-registries = ["docker.io"]' > /etc/containers/registries.conf

if ! grep -q '^Include /etc/ssh/sshd_config.d/\*\.conf' /etc/ssh/sshd_config; then
  printf 'Include /etc/ssh/sshd_config.d/*.conf\n%s\n' "$(cat /etc/ssh/sshd_config)" > /etc/ssh/sshd_config
fi

mkdir -p /var/lib/homelab
chmod 755 /etc/periodic/daily/homelab-upgrade /etc/init.d/homelab-firstboot
rm -rf /var/cache/apk/*
