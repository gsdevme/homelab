# Endpoint and API token are not variables: the provider reads
# PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN from the environment, which
# `op run --env-file=.env.op` fills from 1Password. Neither can reach a
# plan file or the state that way.
provider "proxmox" {
  insecure = var.insecure
}
