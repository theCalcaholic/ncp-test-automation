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
  default = "fsn1"
}

variable "post_setup_script" {
  type = list(string)
  default = []
}

variable "admin_ssh_privkey" {
  type = string
  sensitive = true
}