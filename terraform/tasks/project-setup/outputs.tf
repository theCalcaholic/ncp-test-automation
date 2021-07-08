output "admin_ssh_pubkey_fingerprint" {
  value = hcloud_ssh_key.ssh_key.fingerprint
}
