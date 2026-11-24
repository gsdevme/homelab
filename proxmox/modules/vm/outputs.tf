output "vm_id" {
  description = "Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "ipv4" {
  description = "First non-loopback IPv4 address the QEMU guest agent reports, or null before it reports one."
  value       = try([for a in flatten(proxmox_virtual_environment_vm.this.ipv4_addresses) : a if a != "127.0.0.1"][0], null)
}
