variable "domain" {
  type        = string
  description = "AWS domain to create records in"
}

variable "name_prefix" {
  type    = string
  default = "vaultsrv-"
}

variable "node_count" {
  type    = number
  default = 3
}

variable "email" {
  type = string
}

variable "image_name" {
  type    = string
  default = "rockylinux-9.6"
}

variable "sshkey" {
  type    = string
  default = "vault-node-sshkey"
}

variable "flavor" {
  type    = string
  default = "small"
}

variable "network" {
  type = string
}

variable "vault_license" {
  type = string
}
