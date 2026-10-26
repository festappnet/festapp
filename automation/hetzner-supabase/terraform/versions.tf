terraform {
  required_version = "~> 1.16.0"

  backend "local" {}

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "= 1.68.0"
    }
  }
}

provider "hcloud" {}
