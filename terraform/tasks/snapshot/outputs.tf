output "snapshot_id" {
  value = hcloud_snapshot.ncp-postinstall.id
}

output "snapshot_timestamp" {
  value = data.hcloud_image.snapshot_image_data.created
}
