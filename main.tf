# Random ID for the cluster

resource "random_id" "cluster_id" {
  byte_length = 8
}

locals {
  fqdns = [for i in range(var.node_count) : "${var.name_prefix}-${i}.${var.domain}"]
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

# Generate a private key for the CA
resource "tls_private_key" "dev_ca_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create a self-signed CA certificate
resource "tls_self_signed_cert" "dev_ca_cert" {
  private_key_pem = tls_private_key.dev_ca_key.private_key_pem

  subject {
    common_name  = "Development CA"
    organization = "Dev Team"
  }

  is_ca_certificate = true
  validity_period_hours = 8760 # 1 year validity

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "server_auth",
    "client_auth",
  ]
}

# Vault server nodes certificate
resource "tls_private_key" "cert-key" {
  algorithm = "RSA"
  rsa_bits = 2048
}

resource "tls_cert_request" "vault-server" {
  private_key_pem = tls_private_key.cert-key.private_key_pem

  dns_names = local.fqdns
  subject {
    organization = "HashiCorp"
  }
}

resource "tls_locally_signed_cert" "vault-server" {
  cert_request_pem   = tls_cert_request.vault-server.cert_request_pem
  ca_private_key_pem = tls_private_key.dev_ca_key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.dev_ca_cert.cert_pem

  validity_period_hours = 12

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
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
        ca_cert       = tls_self_signed_cert.dev_ca_cert.cert_pem
        vault_cert    = tls_locally_signed_cert.vault-server.cert_pem
        vault_certkey = tls_private_key.cert-key.private_key_pem
        vault_config  = local.vault-config[fqdn]
      }
    )
  }
}

resource "openstack_compute_keypair_v2" "sshkey" {
  name = "${var.sshkey_prefix}-${random_id.cluster_id.hex}"
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

  tags = [ "cluster_id=${random_id.cluster_id.hex}" ]

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
  hosts_file = [for i in local.fqdns : "${openstack_compute_instance_v2.vault-nodes[i].access_ip_v4} ${i}" ]
}

# Add static entries for DNS on nodes

resource "ssh_resource" "vault-hosts" {
  for_each = toset(local.fqdns)

  bastion_host     = var.ssh_bastion.host
  bastion_user     = var.ssh_bastion.user
  bastion_password = var.ssh_bastion.password

  host     = openstack_compute_instance_v2.vault-nodes[each.key].access_ip_v4
  user     = var.ssh_conn.user
  password = var.ssh_conn.password

  timeout = "30s"

  commands = [
    "echo \"${local.hosts_file[0]}\" | sudo tee -a /etc/hosts",
    "echo \"${local.hosts_file[1]}\" | sudo tee -a /etc/hosts",
    "echo \"${local.hosts_file[2]}\" | sudo tee -a /etc/hosts",
  ]
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

  depends_on = [ssh_resource.vault-hosts]
}
