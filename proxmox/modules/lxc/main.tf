resource "proxmox_virtual_environment_container" "this" {
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = "Managed by OpenTofu from proxmox/ in the homelab repo. Do not edit by hand."
  # Proxmox stores tags lower-case and sorted; anything else shows as a diff.
  tags = sort(distinct([for t in concat(["opentofu"], var.tags) : lower(t)]))

  # Always unprivileged: root in the container is not root on the host.
  unprivileged  = true
  started       = var.started
  start_on_boot = var.start_on_boot

  features {
    nesting = var.nesting
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_size
  }

  network_interface {
    name    = "eth0"
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = var.os_type
  }

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    user_account {
      keys = var.ssh_public_keys
    }
  }

  # Wait for the DHCP lease, so the address is in the outputs after apply.
  wait_for_ip {
    ipv4 = true
  }

  lifecycle {
    # The template and the keys are only read when the container is built,
    # and the provider replaces the container if either changes. Ignoring
    # them means a newer template or a rotated key applies to containers
    # created afterwards instead of destroying the existing ones.
    ignore_changes = [
      operating_system[0].template_file_id,
      initialization[0].user_account,
    ]
  }
}
