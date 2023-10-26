data "hcloud_ssh_key" "admin_key" {
  fingerprint = var.admin_ssh_pubkey_fingerprint
}

module snapshot-provider {
  source = "../../../modules/basic-server"
  ssh_public_keys = [data.hcloud_ssh_key.admin_key.id]
  disk-image = "debian-11"
  server_type = var.server_type

  name = "ncp-postinstall-snapshot-provider${var.uid_suffix}"

  labels = var.uid_suffix == "" ? {} : {ci = trimprefix(var.uid_suffix, "-")}

  admin_ssh_privkey = file(var.admin_ssh_privkey_path)
  post_setup_script = [
    "#!/bin/bash",
    "set -e",
    "export BRANCH=\"${var.branch}\"",
    "export DBG=x",
    "trap 'systemctl stop mariadb; systemctl poweroff' EXIT",
    # Reenable root user for ssh access
    "bash -c 'bash <(wget -O - https://raw.githubusercontent.com/nextcloud/nextcloudpi/${var.branch}/install.sh)' | tee /var/log/ncp-install.log; rc=$?; [[ \"$rc\" == 0 ]] || echo \"SOMETHING WENT WRONG (exit code $?)\"; sed -i '/^root/s/\\/usr\\/sbin\\/nologin/\\/bin\\/bash/' /etc/passwd; exit $rc",
  ]

}
