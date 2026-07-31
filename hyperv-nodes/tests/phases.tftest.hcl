mock_provider "hyperv" {}

run "install_phase_attaches_installer_first" {
  command = plan

  variables {
    installation_phase             = "install"
    installer_iso_present          = true
    install_disk_wipe_confirmation = "asol-k3s-01"
    install_iso_local_path         = "tests/fixtures/test-installer.fixture"
    virtual_switch_name            = "External"
    vm_mac_address                 = "00:15:5D:01:02:03"
  }

  assert {
    condition     = length(hyperv_image_file.installer) == 1
    error_message = "The install phase must upload the installer ISO."
  }

  assert {
    condition     = length(hyperv_vm.node.dvd_drive) == 1
    error_message = "The install phase must attach one DVD drive."
  }

  assert {
    condition     = hyperv_vm.node.boot_order[0].type == "dvd_drive"
    error_message = "The installer DVD must be first in the install-phase boot order."
  }

  assert {
    condition     = hyperv_vm.node.state == null
    error_message = "Terraform must not manage VM power during installation."
  }
}

run "run_phase_detaches_installer" {
  command = plan

  override_data {
    target = data.hyperv_vm_state.power_off_guard
    values = {
      current = "Off"
    }
  }

  variables {
    installation_phase     = "run"
    installer_iso_present  = true
    install_iso_local_path = "tests/fixtures/test-installer.fixture"
    virtual_switch_name    = "External"
    vm_mac_address         = "00:15:5D:01:02:03"
  }

  assert {
    condition     = length(hyperv_image_file.installer) == 1
    error_message = "The guarded run transition must retain the installer file until the DVD is detached."
  }

  assert {
    condition     = length(hyperv_vm.node.dvd_drive) == 0
    error_message = "The run phase must detach the DVD drive."
  }

  assert {
    condition     = length(hyperv_vm.node.boot_order) == 1 && hyperv_vm.node.boot_order[0].type == "hard_disk_drive"
    error_message = "The VHDX must be the only run-phase boot device."
  }

  assert {
    condition     = hyperv_vm.node.state == null
    error_message = "Terraform must not manage VM power during the guarded run transition."
  }
}

run "run_phase_rejects_running_installer" {
  command = plan

  override_data {
    target = data.hyperv_vm_state.power_off_guard
    values = {
      current = "Running"
    }
  }

  variables {
    installation_phase     = "run"
    installer_iso_present  = true
    install_iso_local_path = "tests/fixtures/test-installer.fixture"
    virtual_switch_name    = "External"
    vm_mac_address         = "00:15:5D:01:02:03"
  }

  expect_failures = [
    hyperv_vm.node,
  ]
}

run "operational_phase_allows_iso_cleanup" {
  command = plan

  variables {
    installation_phase             = "operational"
    installer_iso_present          = false
    installer_cleanup_confirmation = "REMOVE_SENSITIVE_ISO_AFTER_BOOTSTRAP:asol-k3s-01"
    install_iso_local_path         = "../does-not-exist.iso"
    virtual_switch_name            = "External"
    vm_mac_address                 = "00:15:5D:01:02:03"
  }

  assert {
    condition     = length(data.hyperv_vm_state.power_off_guard) == 0
    error_message = "Operational plans must not require a powered-off VM."
  }

  assert {
    condition     = length(hyperv_vm.node.dvd_drive) == 0 && hyperv_vm.node.state == null
    error_message = "Operational plans must keep the DVD detached without managing VM power."
  }
}

run "operational_transition_rejects_running_installer" {
  command = plan

  override_data {
    target = data.hyperv_vm_state.power_off_guard
    values = {
      current = "Running"
    }
  }

  variables {
    installation_phase     = "operational"
    installer_iso_present  = true
    install_iso_local_path = "tests/fixtures/test-installer.fixture"
    virtual_switch_name    = "External"
    vm_mac_address         = "00:15:5D:01:02:03"
  }

  expect_failures = [
    hyperv_vm.node,
  ]
}

run "iso_cleanup_requires_confirmation" {
  command = plan

  variables {
    installation_phase    = "operational"
    installer_iso_present = false
    virtual_switch_name   = "External"
    vm_mac_address        = "00:15:5D:01:02:03"
  }

  expect_failures = [
    var.installer_cleanup_confirmation,
  ]
}

run "installer_manifest_rejects_ip_drift" {
  command = plan

  variables {
    installation_phase             = "install"
    installer_iso_present          = true
    install_disk_wipe_confirmation = "asol-k3s-01"
    install_iso_local_path         = "tests/fixtures/test-installer.fixture"
    virtual_switch_name            = "External"
    vm_mac_address                 = "00:15:5D:01:02:03"
    vm_address_cidr                = "192.0.2.32/24"
  }

  expect_failures = [
    hyperv_image_file.installer[0],
  ]
}
