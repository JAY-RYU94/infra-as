terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    hyperv = {
      source  = "registry.terraform.io/windsorcli/hyperv"
      version = "0.3.1"
    }
  }
}
