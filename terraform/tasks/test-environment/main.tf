data "hcloud_ssh_key" "admin_key" {
  fingerprint = var.admin_ssh_pubkey_fingerprint
}

data "hcloud_image" "ncp_image" {
  with_selector = "branch=${replace(var.branch, "/", "-")},type=${var.snapshot_type}"
  most_recent = true
}

module server {
  source = "../../modules/basic-server"
  ssh_public_keys = [data.hcloud_ssh_key.admin_key.id]
  disk-image = data.hcloud_image.ncp_image.id

  name = "ncp-test-server${var.uid_suffix}"

  lables = var.uid_suffix == "" ? {} : {cicd = var.uid_suffix}

  admin_ssh_privkey = file(var.admin_ssh_privkey_path)

}