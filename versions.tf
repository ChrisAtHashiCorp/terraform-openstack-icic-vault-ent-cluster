terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.0"
    }
  }
}
