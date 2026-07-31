locals {
  gib                      = 1024 * 1024 * 1024
  normalized_mac_address   = upper(replace(var.vm_mac_address, ":", ""))
  installer_destination    = var.install_iso_host_path
  installer_attached       = var.installation_phase == "install"
  installer_iso_local_path = abspath(var.install_iso_local_path)
  installer_manifest_path  = "${local.installer_iso_local_path}.manifest.json"
  installer_manifest = (
    var.installer_iso_present && fileexists(local.installer_manifest_path)
    ? jsondecode(file(local.installer_manifest_path))
    : null
  )
}

data "hyperv_virtual_switch" "selected" {
  name = var.virtual_switch_name
}

data "hyperv_vm_state" "power_off_guard" {
  count = (
    var.installation_phase == "run" ||
    (var.installation_phase == "operational" && var.installer_iso_present)
  ) ? 1 : 0
  name = var.vm_name
}

resource "hyperv_image_file" "installer" {
  count = var.installer_iso_present ? 1 : 0

  local_path            = local.installer_iso_local_path
  destination_path      = local.installer_destination
  keep_on_destroy       = false
  force_destroy         = false
  replace_while_mounted = false

  lifecycle {
    precondition {
      condition     = fileexists(local.installer_iso_local_path)
      error_message = "Build the unattended installer ISO before applying this configuration."
    }
    precondition {
      condition     = fileexists(local.installer_manifest_path)
      error_message = "The installer ISO manifest is missing; rebuild the ISO with the repository builder."
    }
    precondition {
      condition = (
        try(local.installer_manifest.schema_version, 0) == 1 &&
        try(local.installer_manifest.vm_hostname, "") == var.vm_name &&
        lower(try(local.installer_manifest.vm_mac_address, "")) == lower(var.vm_mac_address) &&
        try(local.installer_manifest.vm_address_cidr, "") == var.vm_address_cidr
      )
      error_message = "The installer ISO hostname, MAC, or IP manifest does not match the Terraform VM inputs."
    }
    precondition {
      condition = (
        try(local.installer_manifest.iso_sha256, "") ==
        try(filesha256(local.installer_iso_local_path), "")
      )
      error_message = "The installer ISO checksum does not match its manifest; rebuild it before apply."
    }
  }
}

resource "hyperv_vhd" "node" {
  path       = var.vhd_path
  vhd_type   = "dynamic"
  size_bytes = var.vhd_size_gib * local.gib

  lifecycle {
    prevent_destroy = true
  }
}

resource "hyperv_vm" "node" {
  name       = var.vm_name
  generation = 2

  cpu = {
    count = var.processor_count
  }

  memory = {
    startup_bytes = var.memory_gib * local.gib
    dynamic       = false
  }

  network_adapter = [
    {
      name        = "eth0"
      switch_name = data.hyperv_virtual_switch.selected.name
      mac_address = local.normalized_mac_address
    }
  ]

  hard_disk_drive = [
    {
      path                = hyperv_vhd.node.path
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 0
    }
  ]

  dvd_drive = local.installer_attached ? [
    {
      iso_path            = hyperv_image_file.installer[0].destination_path
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 1
    }
  ] : []

  boot_order = local.installer_attached ? [
    {
      type                = "dvd_drive"
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 1
    },
    {
      type                = "hard_disk_drive"
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 0
    }
    ] : [
    {
      type                = "hard_disk_drive"
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 0
    }
  ]

  secure_boot          = true
  secure_boot_template = "MicrosoftUEFICertificateAuthority"

  lifecycle {
    precondition {
      condition = (
        var.installation_phase == "install" ||
        (var.installation_phase == "operational" && !var.installer_iso_present) ||
        data.hyperv_vm_state.power_off_guard[0].current == "Off"
      )
      error_message = "The VM must be Off before detaching the installer DVD or entering operational phase with the ISO retained."
    }
  }

  depends_on = [
    hyperv_vhd.node,
    hyperv_image_file.installer,
  ]
}
