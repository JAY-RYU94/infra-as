variable "installation_phase" {
  description = "VM boot phase: install, guarded run transition while Off, then operational."
  type        = string
  default     = "install"

  validation {
    condition     = contains(["install", "run", "operational"], var.installation_phase)
    error_message = "installation_phase must be install, run, or operational."
  }
}

variable "installer_iso_present" {
  description = "Keep the generated installer ISO on the Hyper-V host. Set false only after the run phase has detached it."
  type        = bool
  default     = true

  validation {
    condition     = var.installer_iso_present || var.installation_phase == "operational"
    error_message = "The installer ISO must remain present through the install and guarded run phases."
  }
}

variable "installer_cleanup_confirmation" {
  description = "Confirmation required before removing the sensitive installer ISO after bootstrap verification."
  type        = string
  default     = ""

  validation {
    condition = var.installer_iso_present || (
      var.installation_phase == "operational" &&
      var.installer_cleanup_confirmation == "REMOVE_SENSITIVE_ISO_AFTER_BOOTSTRAP:${var.vm_name}"
    )
    error_message = "To remove the ISO, use operational phase and set installer_cleanup_confirmation to REMOVE_SENSITIVE_ISO_AFTER_BOOTSTRAP:<vm_name>."
  }
}

variable "install_disk_wipe_confirmation" {
  description = "Explicit confirmation for destructive autoinstall. During install this must exactly match vm_name."
  type        = string
  default     = ""

  validation {
    condition     = var.installation_phase != "install" || var.install_disk_wipe_confirmation == var.vm_name
    error_message = "During the install phase, install_disk_wipe_confirmation must exactly match vm_name."
  }
}

variable "install_iso_local_path" {
  description = "Path on the OpenTofu runner to the generated unattended Ubuntu ISO."
  type        = string
  default     = "../.artifacts/asol-k3s-ubuntu-24.04.4-autoinstall.iso"
}

variable "install_iso_host_path" {
  description = "Destination path for the installer ISO on the Hyper-V host."
  type        = string
  default     = "C:/Hyper-V/ASOL/ISO/asol-k3s-ubuntu-24.04.4-autoinstall.iso"
}

variable "vm_name" {
  description = "Hyper-V virtual machine name and Ubuntu hostname."
  type        = string
  default     = "asol-k3s-01"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.vm_name))
    error_message = "vm_name must be a lowercase DNS label of at most 63 characters."
  }
}

variable "vhd_path" {
  description = "Destination VHDX path on the Hyper-V host."
  type        = string
  default     = "C:/Hyper-V/ASOL/VHDX/asol-k3s-01.vhdx"
}

variable "vhd_size_gib" {
  description = "Maximum size in GiB of the dynamically expanding VHDX."
  type        = number
  default     = 1024

  validation {
    condition     = var.vhd_size_gib >= 200
    error_message = "vhd_size_gib must be at least 200 GiB."
  }
}

variable "processor_count" {
  description = "Number of virtual processors."
  type        = number
  default     = 8

  validation {
    condition     = var.processor_count >= 4 && floor(var.processor_count) == var.processor_count
    error_message = "processor_count must be an integer of at least 4."
  }
}

variable "memory_gib" {
  description = "Fixed startup memory in GiB. Dynamic Memory is intentionally disabled."
  type        = number
  default     = 32

  validation {
    condition     = var.memory_gib >= 16
    error_message = "memory_gib must be at least 16 GiB."
  }
}

variable "virtual_switch_name" {
  description = "Name of an existing Hyper-V External virtual switch."
  type        = string

  validation {
    condition     = trimspace(var.virtual_switch_name) != ""
    error_message = "virtual_switch_name must not be empty."
  }
}

variable "vm_mac_address" {
  description = "Static Hyper-V MAC address in colon-delimited form, also used by Ubuntu netplan."
  type        = string

  validation {
    condition     = can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", var.vm_mac_address))
    error_message = "vm_mac_address must have the form 00:15:5D:01:02:03."
  }
}

variable "vm_address_cidr" {
  description = "Static Ubuntu IPv4 CIDR, checked against the generated ISO manifest."
  type        = string
  default     = "192.0.2.31/24"

  validation {
    condition     = can(cidrnetmask(var.vm_address_cidr)) && !strcontains(var.vm_address_cidr, ":")
    error_message = "vm_address_cidr must be a valid IPv4 CIDR."
  }
}
