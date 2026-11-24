# Add an output per container module so `tofu output` shows its VM ID and
# address, e.g.
#
#   output "example" {
#     value = { vm_id = module.example.vm_id, ipv4 = module.example.ipv4 }
#   }

output "vms" {
  description = "VM ID and IPv4 address of each test VM, by name."
  value = {
    for name, vm in module.test_vm : name => { vm_id = vm.vm_id, ipv4 = vm.ipv4 }
  }
}
