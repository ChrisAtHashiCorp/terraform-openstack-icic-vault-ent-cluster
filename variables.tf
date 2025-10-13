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
  default = "hashistack"
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

variable "ssh_bastion" {
  sensitive = true
  type = object({
    host     = optional(string, null)
    port     = optional(string, "22")
    user     = optional(string, null)
    password = optional(string, null)
  })
  default = {}
}

variable "ssh_conn" {
  sensitive = true
  type = object({
    user     = optional(string, "rocky")
    password = optional(string, null)
  })
  default = {}
}
