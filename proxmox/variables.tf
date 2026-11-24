# Facts about the Proxmox host as it is, so the repo stays the description
# of what is running. Change them here when the host changes.

variable "node_name" {
  description = "Proxmox node the guests are created on."
  type        = string
  default     = "venus"
}

variable "guest_datastore" {
  description = "Datastore for guest root disks."
  type        = string
  default     = "local-lvm"
}

variable "template_datastore" {
  description = "Datastore that holds container templates (needs the 'Container template' content type)."
  type        = string
  default     = "local"
}

variable "bridge" {
  description = "Bridge the guests attach to."
  type        = string
  default     = "vmbr0"
}

variable "insecure" {
  description = "Skip TLS verification of the Proxmox API. True suits the self-signed certificate Proxmox ships with."
  type        = bool
  default     = true
}

variable "debian_lxc_template_url" {
  description = "Debian container template to download. List what is current with `pveam available --section system` on the node."
  type        = string
  default     = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
}

# Comes from 1Password through .env.op as TF_VAR_ssh_public_key.
variable "ssh_public_key" {
  description = "SSH public key authorised for root in every guest."
  type        = string

  validation {
    condition     = can(regex("^(ssh-|ecdsa-|sk-)", trimspace(var.ssh_public_key)))
    error_message = "Not an SSH public key. Is tofu running under `op run --env-file=.env.op`?"
  }
}
