variable "namecheap_user_name" {
  type = string
}

variable "namecheap_api_key" {
  type = string
}

variable "namecheap_domain" {
  type = string
}

variable "namecheap_hostname" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_vpc_id" {
  type = string
}

variable "aws_availability_zone" {
  type = string
}

variable "aws_subnet_id" {
  type = string
}

variable "aws_private_ip" {
  type = string
}

variable "aws_instance_type" {
  type = string
}

variable "aws_instance_arch" {
  type = string
}

variable "mumble_docker_image" {
  type    = string
  default = "mumblevoip/mumble-server:latest"
}

variable "minecraft_docker_image" {
  type    = string
  default = "itzg/minecraft-server:java17-alpine"
}

variable "minecraft_java_xms" {
  type    = string
  default = "64M"
}

variable "minecraft_java_xmx" {
  type    = string
  default = "1500M"
}
