variable "disk-image" {
  type = string
}
variable "ssh_public_keys" {
  type = list(number)
}

variable "name" {
  type = string
}

variable "server_type" {
  default = "cx11"
}

variable "location" {
  default = "hel1"
}

variable "post_setup_script" {
  type = list(string)
  default = ["true"]
}

variable "admin_ssh_privkey" {
  type = string
  sensitive = true
}

variable "labels" {
    type = map(string)
  default = {}
}
