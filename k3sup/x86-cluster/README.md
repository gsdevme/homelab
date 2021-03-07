# Pi k3s Cluster

K3s cluster is installed with [k3sup](https://github.com/alexellis/k3sup#create-a-multi-master-ha-setup-with-embedded-etcd) and using the embedded etcd requiring a minimum of 3x nodes.

## Network

| Hostname      | IP |
| ----------- | ----------- |
| vip      | 172.16.16.80       |
| kube-master-1      | 172.16.16.81       |
| kube-master-2   | 172.16.16.82        |
| kube-master-3   | 172.16.16.83        |

##

```bash

```

## Keepalive

To operate the virtual IP address keepalive is installed on each "master" node to act as a single IP for speaking via kubectl

```bash
# /etc/keepalived/keepalived.conf
#
# apt install keepalive -y
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass xxxxxxx
    }
    virtual_ipaddress {
        172.16.16.80
    }
}
```
