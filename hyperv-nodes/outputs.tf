output "vm_name" {
  description = "Created Hyper-V virtual machine name."
  value       = hyperv_vm.node.name
}

output "vm_ip_addresses" {
  description = "IP addresses reported by Hyper-V integration services after Ubuntu boots."
  value       = hyperv_vm.node.ip_addresses
}

output "vhd_path" {
  description = "Managed VHDX path on the Hyper-V host."
  value       = hyperv_vhd.node.path
}

output "next_step" {
  description = "Required next action in the install, guarded run, and operational workflow."
  value = var.installation_phase == "install" ? (
    "Start the VM exactly once from Hyper-V, wait for autoinstall to power it off, set installation_phase=\"run\", and apply again."
    ) : (
    var.installation_phase == "run" ?
    "Set installation_phase=\"operational\", apply once more while the VM is Off, then start it exactly once from Hyper-V." :
    (
      var.installer_iso_present ?
      "If not already running, start the VM from Hyper-V; after cloud-init and k3s are healthy, confirm cleanup and remove the sensitive ISO." :
      "Ubuntu is operational and the installer ISO is no longer managed on the Hyper-V host."
    )
  )
}
