# Add an output per container or VM module so `tofu output` shows its VM ID
# and address, e.g.
#
#   output "example" {
#     value = { vm_id = module.example.vm_id, ipv4 = module.example.ipv4 }
#   }
