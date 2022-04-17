variable "admin_ssh_pubkey_path" {
  type = string
}
variable "hcloud_api_token" {
  type = string
  sensitive = true
}

variable "uid_suffix" {
  type = string
  default = ""
}