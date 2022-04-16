variable "hcloud_api_token" {
  type = string
  sensitive = true
}

variable "admin_ssh_pubkey_fingerprint" {
  type = string
}

variable "admin_ssh_privkey_path" {
  type = string
}

variable "branch" {
  default = "devel"
}