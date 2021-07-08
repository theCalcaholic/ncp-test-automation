resource "hcloud_snapshot" "ncp-postinstall" {
  server_id = var.snapshot_provider_id
  description = "postinstall snapshot for ${var.branch} branch"

  labels = {
    branch = var.branch
    type = "ncp-postinstall"
  }
}

data "hcloud_image" "snapshot_image_data" {
  id = hcloud_snapshot.ncp-postinstall.id
}
