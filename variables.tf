variable "allowed_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Allow these security groups to the resources created in this module"
}

variable "aurora_endpoint" {
  type        = string
  description = "The Aurora cluster endpoint"
}

variable "aurora_port" {
  type        = string
  description = "The Aurora cluster port"
}

variable "email" {
  type        = string
  description = "The email address of the super user"
}

variable "kms_key_arn" {
  type        = string
  description = "The AWS KMS key ARN to use for the encryption"
}

variable "name" {
  type        = string
  description = "The name of the Netbox instance"
}

variable "netbox_version" {
  type        = string
  description = "The version of Netbox"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "The public subnets of the VPC"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "The private subnets of the VPC"
}

variable "repository_credentials_username" {
  type        = string
  description = "The username to use when accessing the container repository"
}

variable "repository_credentials_password" {
  type        = string
  description = "The password to use when accessing the container repository"
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags to assign to the resources"
}

variable "vpc_id" {
  type        = string
  description = "The VPC ID"
}

variable "zone_id" {
  type        = string
  description = "ID of the Route53 zone in which to create the subdomain record"
}
