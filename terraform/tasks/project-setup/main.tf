resource "hcloud_ssh_key" "ssh_key" {
  name = "root${var.uid_suffix}"
  public_key = file(var.admin_ssh_pubkey_path)
}