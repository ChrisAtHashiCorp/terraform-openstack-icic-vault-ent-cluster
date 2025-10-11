output "fqdns" {
  value = local.fqdns
}

output "unseal_keys" {
  value = local.vault_init_res.unseal_keys_b64
}

output "root_token" {
  value = local.vault_init_res.root_token
}
