locals {
  fqdns = [for i in range(var.node_count) : "${var.name_prefix}${i}.${var.domain}"]
}

# Create DNS records for instances

data "aws_route53_zone" "domain" {
  name = var.domain
}

resource "aws_route53_record" "fqdns" {
  for_each = toset(local.fqdns)

  zone_id = data.aws_route53_zone.domain.zone_id
  name    = each.value
  type    = "A"
  ttl     = 30
  records = [openstack_compute_instance_v2.vault-nodes[each.key].access_ip_v4]
}

# Create TLS certificates for the servers 

resource "acme_registration" "reg" {
  email_address = var.email
}

resource "acme_certificate" "certificate" {
  account_key_pem           = acme_registration.reg.account_key_pem
  subject_alternative_names = local.fqdns

  dns_challenge {
    provider = "route53"

    config = {
      AWS_DEFAULT_REGION = "us-east-1"
    }
  }
}

# Create Vault server nodes

data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}

locals {
  vault-config = {
    for fqdn in local.fqdns : fqdn => templatefile("${path.module}/provision/vault.hcl.tftpl",
      {
        fqdn      = fqdn
        srvr_list = setsubtract(toset(local.fqdns), toset([fqdn]))
      }
    )
  }

  user-data = {
    for fqdn in local.fqdns : fqdn => templatefile("${path.module}/provision/cloud-init.yml.tftpl",
      {
        vault_license = var.vault_license
        ca_cert       = acme_certificate.certificate.issuer_pem
        vault_cert    = acme_certificate.certificate.certificate_pem
        vault_certkey = acme_certificate.certificate.private_key_pem
        vault_config  = local.vault-config[fqdn]
      }
    )
  }
}

resource "openstack_compute_keypair_v2" "sshkey" {
  name = var.sshkey
}

resource "openstack_compute_instance_v2" "vault-nodes" {
  for_each = toset(local.fqdns)

  name        = each.value
  image_id    = data.openstack_images_image_v2.image.id
  flavor_name = var.flavor
  key_pair    = openstack_compute_keypair_v2.sshkey.name
  user_data   = local.user-data[each.key]

  network {
    name = var.network
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Initiate Vault Cluster

resource "ssh_resource" "vault-init" {
  bastion_host     = var.ssh_bastion.host
  bastion_user     = var.ssh_bastion.user
  bastion_password = var.ssh_bastion.password

  host     = openstack_compute_instance_v2.vault-nodes[local.fqdns[0]].access_ip_v4
  user     = var.ssh_conn.user
  password = var.ssh_conn.password

  commands = [
    "vault operator init -tls-skip-verify -format=json"
  ]

  lifecycle {
    ignore_changes = all
  }
}

locals {
  vault_init_res = jsondecode(ssh_resource.vault-init.result)
}

# Unseal Vault Cluster nodes

resource "ssh_resource" "vault-unseal" {
  for_each = toset(local.fqdns)

  bastion_host     = var.ssh_bastion.host
  bastion_user     = var.ssh_bastion.user
  bastion_password = var.ssh_bastion.password

  host     = openstack_compute_instance_v2.vault-nodes[each.key].access_ip_v4
  user     = var.ssh_conn.user
  password = var.ssh_conn.password

  timeout = "30s"

  commands = [
    "vault operator unseal -tls-skip-verify ${local.vault_init_res.unseal_keys_b64[0]}",
    "vault operator unseal -tls-skip-verify ${local.vault_init_res.unseal_keys_b64[1]}",
    "vault operator unseal -tls-skip-verify ${local.vault_init_res.unseal_keys_b64[2]}",
  ]
}
