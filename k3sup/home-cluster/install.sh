#!/bin/bash

which /usr/local/bin/k3sup

if [ $? -eq 1 ]; then
    echo "k3sup not installed"
    echo "run 'curl -sLS https://get.k3sup.dev | sh'"
    exit 1
fi

# keepalive VIP
KUBE_VIP="172.16.16.17"
LB="$KUBE_VIP"

VERSION="v1.27.16+k3s1"

SSH_USER="root"

#ALL=("172.16.16.81" "172.16.16.86" "172.16.16.85" )
MASTER_ONE="172.16.16.17"
#MASTERS=("172.16.16.86" "172.16.16.85")
AGENTS=( "172.16.16.60" "172.16.16.62" "172.16.16.61")
#AGENTS=( "172.16.16.61")

for ip in "${ALL[@]}"
do
   :
  ssh root@$ip "apt-get install curl vim htop lm-sensors open-iscsi sudo -y"
done

EXTRA_ARGS="--write-kubeconfig-mode 0664 --disable traefik,servicelb local-storage --tls-san $KUBE_VIP"

#k3sup install \
# --ip $MASTER_ONE \
# --user $SSH_USER \
# --cluster \
# --k3s-extra-args "$EXTRA_ARGS"  \
# --k3s-version $VERSION

#
#for ip in "${MASTERS[@]}"
#do
#   :
#  k3sup join \
#    --ip $ip \
#    --user $SSH_USER \
#    --server-user $SSH_USER \
#    --server-ip $KUBE_VIP \
#    --server \
#    --k3s-extra-args "$EXTRA_ARGS" \
#    --k3s-version $VERSION
#
#    # allow each node time
#    sleep 60
#done

# for ip in "${AGENTS[@]}"
# do
#    :
#   k3sup join \
#     --ip $ip \
#     --user pi \
#     --server-user root \
#     --server-ip $KUBE_VIP \
#     --k3s-version $VERSION
#
#     # allow each node time
#     sleep 60
# done
