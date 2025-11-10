output "fqdns" {
  value = local.fqdns
}

output "ca_cert" {
  value = tls_self_signed_cert.dev_ca_cert
}

output "unseal_keys" {
  value = local.vault_init_res.unseal_keys_b64
}

output "root_token" {
  value = local.vault_init_res.root_token
}
