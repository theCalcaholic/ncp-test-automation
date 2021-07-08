resource "hcloud_ssh_key" "ssh_key" {
  name = "root"
  public_key = file(var.admin_ssh_pubkey_path)
}