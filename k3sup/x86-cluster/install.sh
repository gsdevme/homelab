#!/bin/bash

which /usr/local/bin/k3sup

if [ $? -eq 1 ]; then
    echo "k3sup not installed"
    echo "run 'curl -sLS https://get.k3sup.dev | sh'"
    exit 1
fi

# keepalive VIP
KUBE_VIP="172.16.16.80"
LB="$KUBE_VIP"

VERSION="v1.20.9+k3s1"

SSH_USER="root"

ALL=("172.16.16.81" "172.16.16.82" "172.16.16.86" "172.16.16.85")
MASTER_ONE="172.16.16.81"
MASTERS=("172.16.16.82" "172.16.16.86" "172.16.16.85")

for ip in "${ALL[@]}"
do
   :
  ssh root@$ip "apt-get install curl vim htop lm-sensors open-iscsi sudo -y"
done

EXTRA_ARGS="--write-kubeconfig-mode 0664 --no-deploy traefik --tls-san $KUBE_VIP"

k3sup install \
  --ip $MASTER_ONE \
  --user $SSH_USER \
  --cluster \
  --k3s-extra-args "$EXTRA_ARGS"  \
  --k3s-version $VERSION

# give the box a two seconds to get to grips with its new world
sleep 2

for ip in "${MASTERS[@]}"
do
   :
  k3sup join \
    --ip $ip \
    --user $SSH_USER \
    --server-user $SSH_USER \
    --server-ip $KUBE_VIP \
    --server \
    --k3s-extra-args "$EXTRA_ARGS" \
    --k3s-version $VERSION
done
