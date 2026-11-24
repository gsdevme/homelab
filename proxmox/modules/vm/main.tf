# One QEMU virtual machine whose root disk is imported from a cloud image
# already on the node (an `import` content file, e.g. the id of a
# proxmox_download_file). Proxmox's own cloud-init drive sets the root key,
# hostname and network, so tofu never needs SSH to the host or the guest.
#
# lifecycle.ignore_changes: the image and the keys are only read when the
# VM is built, and the provider replaces the VM if either changes. Ignoring
# them means a newer weekly image or a rotated key applies to VMs created
# afterwards instead of destroying the existing ones.
resource "proxmox_virtual_environment_vm" "this" {
  name        = var.hostname
  vm_id       = var.vm_id
  node_name   = var.node_name
  description = var.description
  # Proxmox stores tags lower-case and sorted; anything else shows as a diff.
  tags = sort(distinct([for t in concat(["opentofu"], var.tags) : lower(t)]))

  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"

  on_boot         = var.start_on_boot
  started         = var.started
  stop_on_destroy = true

  timeout_create      = 1800
  timeout_shutdown_vm = 300

  agent {
    enabled = true
    timeout = "15m"
  }

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    import_from  = var.image_file_id
    size         = var.disk_size
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
    model   = "virtio"
  }

  serial_device {}

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.datastore_id

    user_account {
      username = "root"
      keys     = var.ssh_public_keys
    }

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [
      disk[0].import_from,
      initialization[0].user_account,
    ]
  }
}
