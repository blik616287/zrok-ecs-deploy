data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ECS-optimized Amazon Linux 2023 AMI for arm64 (Graviton / t4g).
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

# The VPC's Internet Gateway (used to give our subnet a real public route).
data "aws_internet_gateway" "vpc" {
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}
