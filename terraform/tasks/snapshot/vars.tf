variable "snapshot_provider_id" {
  type = number
}
variable "hcloud_ncp_playground_api_token" {
  type = string
  sensitive = true
}
variable "branch" {
  type = string
}