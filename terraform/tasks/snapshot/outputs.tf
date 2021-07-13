output "snapshot_id" {
  value = data.hcloud_image.snapshot_image_data.id
}

output "snapshot_timestamp" {
  value = data.hcloud_image.snapshot_image_data.created
}
