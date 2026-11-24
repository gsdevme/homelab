variable "hostname" {
  description = "Container hostname."
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID. Set explicitly so a container can be imported back by ID if the state is ever lost."
  type        = number
}

variable "node_name" {
  description = "Proxmox node to create the container on."
  type        = string
}

variable "template_file_id" {
  description = "Container template, e.g. the id of a proxmox_download_file."
  type        = string
}

variable "os_type" {
  description = "Distribution family of the template."
  type        = string
  default     = "debian"
}

variable "ssh_public_keys" {
  description = "SSH public keys authorised for root. Only applied when the container is created."
  type        = list(string)
}

variable "datastore_id" {
  description = "Datastore for the root disk."
  type        = string
}

variable "disk_size" {
  description = "Root disk size in GB."
  type        = number
  default     = 4
}

variable "cores" {
  description = "CPU cores."
  type        = number
  default     = 1
}

variable "memory" {
  description = "Memory in MB."
  type        = number
  default     = 512
}

variable "swap" {
  description = "Swap in MB."
  type        = number
  default     = 0
}

variable "bridge" {
  description = "Bridge eth0 attaches to."
  type        = string
}

variable "vlan_id" {
  description = "VLAN tag for eth0. Null for untagged."
  type        = number
  default     = null
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

variable "nesting" {
  description = "Allow nesting. systemd in current Debian templates needs it in an unprivileged container."
  type        = bool
  default     = true
}

variable "started" {
  description = "Whether the container should be running."
  type        = bool
  default     = true
}

variable "start_on_boot" {
  description = "Start the container when the node boots."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra Proxmox tags. \"opentofu\" is always added."
  type        = list(string)
  default     = []
}
