resource "hcloud_ssh_key" "ssh_keys" {
  for_each = toset([var.admin_ssh_pubkey])
  name = "root"
  public_key = each.value
}

module server {
  source = "../../modules/basic-server"
  ssh_public_keys = length(hcloud_ssh_key.ssh_keys) == 1 ? [hcloud_ssh_key.ssh_keys[var.admin_ssh_pubkey].id] : [for k in hcloud_ssh_key.ssh_keys: k.id]
  disk-image = "debian-10"

  name = "ncp-install-test"

  admin_ssh_privkey = file(var.admin_ssh_privkey_path)
  post_setup_script = ["wget -O - https://raw.githubusercontent.com/nextcloud/nextcloudpi/${var.branch}/install.sh | bash"]

}
