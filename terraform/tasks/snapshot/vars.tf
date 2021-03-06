variable "snapshot_provider_id" {
  type = number
}

variable "hcloud_api_token" {
  type = string
  sensitive = true
}

variable "snapshot_type" {
  type = string
}

variable "branch" {
  type = string
}

variable "uid_suffix" {
  type = string
  default = ""
}