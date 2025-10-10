output "fqdns" {
  value = local.fqdns
}

output "unseal_keys" {
  value = local.vault_unseal_keys
}

output "root_token" {
  value = local.vault_root_token
}
