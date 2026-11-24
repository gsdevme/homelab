variable "hostname" {
  description = "VM name and guest hostname."
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID. Set explicitly so a VM can be imported back by ID if the state is ever lost."
  type        = number
}

variable "node_name" {
  description = "Proxmox node to create the VM on."
  type        = string
}

variable "datastore_id" {
  description = "Datastore for the root disk and the cloud-init drive."
  type        = string
}

variable "bridge" {
  description = "Bridge the network device attaches to."
  type        = string
}

variable "image_file_id" {
  description = "Cloud image imported as the root disk, e.g. the id of a proxmox_download_file with content_type \"import\". Only read when the VM is created."
  type        = string
}

variable "ssh_public_keys" {
  description = "SSH public keys authorised for root. Only applied when the VM is created."
  type        = list(string)
}

variable "cores" {
  description = "CPU cores."
  type        = number
  default     = 1
}

variable "memory" {
  description = "Memory in MB."
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Root disk size in GB. The image is grown to this on import."
  type        = number
  default     = 16

  validation {
    condition     = var.disk_size >= 8
    error_message = "disk_size must be at least 8 GB."
  }
}

variable "ipv4_address" {
  description = "\"dhcp\", or a static address in CIDR form such as 172.16.16.50/24."
  type        = string
  default     = "dhcp"
}

variable "ipv4_gateway" {
  description = "Gateway for a static address. Leave null with DHCP."
  type        = string
  default     = null
}

variable "vlan_id" {
  description = "VLAN tag for the network device. Null for untagged."
  type        = number
  default     = null
}

variable "started" {
  description = "Whether the VM should be running."
  type        = bool
  default     = true
}

variable "start_on_boot" {
  description = "Start the VM when the node boots."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra Proxmox tags. \"opentofu\" is always added."
  type        = list(string)
  default     = []
}

variable "description" {
  description = "Description shown in the Proxmox UI."
  type        = string
  default     = "Managed by OpenTofu from proxmox/ in the homelab repo. Do not edit by hand."
}
