output "test_server_name" {
  value = module.server.name
}

output "test_server_ipv4" {
  value = module.server.ipv4
}

output "test_server_ipv6" {
  value = module.server.ipv6
}

output "snapshot_id" {
  value = data.hcloud_image.postinstall_image.id
}