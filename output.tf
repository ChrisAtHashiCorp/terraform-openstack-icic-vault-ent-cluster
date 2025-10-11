output "fqdns" {
  value = local.fqdns
}

output "unseal_keys" {
  value = local.vault_init_res
}

output "root_token" {
  value = local.vault_init_res
}
