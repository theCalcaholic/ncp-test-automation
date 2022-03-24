data "hcloud_ssh_key" "admin_key" {
  fingerprint = var.admin_ssh_pubkey_fingerprint
}

module snapshot-provider {
  source = "../../../modules/basic-server"
  ssh_public_keys = [data.hcloud_ssh_key.admin_key.id]
  disk-image = "debian-11"

  name = "ncp-postinstall-snapshot-provider"

  admin_ssh_privkey = file(var.admin_ssh_privkey_path)
  post_setup_script = [
    "set -e",
    "export BRANCH=\"${var.branch}\"",
    "bash -c 'bash <(wget -O - https://raw.githubusercontent.com/nextcloud/nextcloudpi/${var.branch}/install.sh)' | tee /var/log/ncp-install.log",
    "systemctl poweroff"
  ]

}
