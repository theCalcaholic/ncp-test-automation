resource "hcloud_server" "server" {
  image = var.disk-image
  name = var.name
  server_type = var.server_type
  location = var.location
  ssh_keys = var.ssh_public_keys

  labels = var.labels

  provisioner "remote-exec" {
    inline = var.post_setup_script

    connection {
      type     = "ssh"
      user     = "root"
      private_key = "${var.admin_ssh_privkey}"
      host     = self.ipv4_address
      timeout  = "15m"
    }
  }

}
