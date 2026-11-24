output "vm_id" {
  description = "Proxmox VM ID."
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "ipv4" {
  description = "IPv4 address per interface, once the container is running."
  value       = proxmox_virtual_environment_container.this.ipv4
}
