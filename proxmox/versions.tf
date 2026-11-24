terraform {
  required_version = ">= 1.10"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.123.1"
    }
  }

  # State is a plain file on the machine that runs tofu. Where it lives is
  # set per machine in the gitignored backend.hcl (see backend.hcl.example),
  # so moving it later is a path change and `tofu init -migrate-state`.
  backend "local" {}
}
