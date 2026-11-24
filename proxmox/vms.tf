# Every virtual machine on the host is declared here as a `modules/vm`
# instance. The two test VMs prove each weekly image boots, takes the key
# and gets a DHCP address.
locals {
  test_vms = {
    tofu-vm-debian = { vm_id = 9101, image = proxmox_download_file.debian_vm.id }
    tofu-vm-alpine = { vm_id = 9102, image = proxmox_download_file.alpine_vm.id }
  }
}

module "test_vm" {
  source   = "./modules/vm"
  for_each = local.test_vms

  hostname        = each.key
  vm_id           = each.value.vm_id
  image_file_id   = each.value.image
  node_name       = var.node_name
  datastore_id    = var.guest_datastore
  bridge          = var.bridge
  ssh_public_keys = [trimspace(var.ssh_public_key)]
  tags            = ["test"]
}
