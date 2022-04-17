resource "hcloud_snapshot" "ncp-snapshot" {
  server_id = var.snapshot_provider_id
  description = "${var.snapshot_type} snapshot for ${var.branch} branch%{ if var.uid_suffix == ""}(CICD/${var.uid_suffix})%{ endif }"

  labels = {
    branch = replace(var.branch, "/", "-")
    type = var.snapshot_type
    test-result = "none"
    cicd = "%{ if var.uid_suffix == "" }${var.uid_suffix}%{ else }none%{ endif }"
  }
}

data "hcloud_image" "snapshot_image_data" {
  id = hcloud_snapshot.ncp-snapshot.id
}
