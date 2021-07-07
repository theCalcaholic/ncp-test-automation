output "server" {
  value = hcloud_server.server
}

output "name" {
  value = var.name
}

output "ipv4" {
  value = hcloud_server.server.ipv4_address
}

output "ipv6" {
  value = hcloud_server.server.ipv6_address
}
