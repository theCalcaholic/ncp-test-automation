data "hcloud_ssh_key" "admin_key" {
  fingerprint = var.admin_ssh_pubkey_fingerprint
}

data "hcloud_image" "postinstall_image" {
  with_selector = "branch=${var.branch},type=ncp-postinstall"
  most_recent = true
}

module server {
  source = "../../../modules/basic-server"
  ssh_public_keys = [data.hcloud_ssh_key.admin_key.id]
  disk-image = data.hcloud_image.postinstall_image.id

  name = "ncp-install-test"

  admin_ssh_privkey = file(var.admin_ssh_privkey_path)

}