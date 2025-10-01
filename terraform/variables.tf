# Region where all AWS resources will be deployed
variable "region" {
  type    = string
  default = "us-east-1"
}

# Instance type for Elasticsearch (t3.small ~ $10-15/mo)
variable "es_instance_type" {
  type    = string
  default = "t3.small"
}

# Optional SSH key name (if you want to log into EC2)
variable "ssh_key_name" {
  type    = string
  default = null
}

