variable "region" {
  type    = string
  default = "us-east-2"
}

variable "profile" {
  description = "AWS CLI/SDK profile. Leave null to use the default credential chain (env, SSO, instance role)."
  type        = string
  default     = null
}

variable "dns_zone" {
  description = "zrok DNS zone; a wildcard *.<dns_zone> is created pointing at the EIP (e.g. share.example.com)."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID that contains dns_zone."
  type        = string
}

variable "vpc_id" {
  description = "VPC to deploy into."
  type        = string
}

variable "subnet_id" {
  description = "Single public subnet (one AZ) for the container instance."
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t4g.small" # arm64, ~$12/mo; bump to t4g.medium if memory-tight
}

variable "root_volume_gb" {
  type    = number
  default = 30
}

variable "admin_ssh_cidr" {
  description = "CIDR allowed SSH (22). Empty = no SSH ingress (use SSM Session Manager)."
  type        = string
  default     = ""
}

# Container images (pin tags for reproducible deploys).
variable "ziti_controller_image" {
  type    = string
  default = "docker.io/openziti/ziti-controller:latest"
}
variable "ziti_router_image" {
  type    = string
  default = "docker.io/openziti/ziti-router:latest"
}
variable "zrok2_image" {
  type    = string
  default = "docker.io/openziti/zrok2:latest"
}
variable "postgres_image" {
  type    = string
  default = "postgres:16-alpine"
}
variable "rabbitmq_image" {
  type    = string
  default = "rabbitmq:3-management-alpine"
}

# Ports (match the compose defaults).
variable "ziti_ctrl_port" {
  type    = number
  default = 1280
}
variable "ziti_router_port" {
  type    = number
  default = 3022
}
variable "zrok2_ctrl_port" {
  type    = number
  default = 18080
}
variable "zrok2_frontend_port" {
  type    = number
  default = 8080
}
variable "ziti_user" {
  type    = string
  default = "admin"
}
variable "ziti_router_name" {
  type    = string
  default = "zrok2-router"
}

# Placeholder for imported SSM SecureString params. Real values already live in
# SSM and are preserved via lifecycle ignore_changes = [value]; this is only used
# if a parameter is ever created fresh.
variable "ssm_placeholder" {
  type      = string
  default   = "CHANGE_ME_IN_SSM"
  sensitive = true
}
