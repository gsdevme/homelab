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

variable "images_repository" {
  description = "GitHub repository whose releases carry the weekly VM images."
  type        = string
  default     = "gsdevme/homelab"
}

variable "images_release" {
  description = "Image release to download, tagged images-YYYYMMDD. Move it forward to pick up a newer weekly build; existing VMs keep the image they were created from."
  type        = string
  default     = "images-20261125-b0170f0"

  validation {
    condition     = can(regex("^images-[0-9]{8}$", var.images_release))
    error_message = "images_release must look like images-YYYYMMDD."
  }
}

variable "images_datastore" {
  description = "Datastore the VM images are downloaded to (needs the 'Import' content type)."
  type        = string
  default     = "local"
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
