# Stable public address. OpenZiti bakes advertised DNS names into its config at
# bootstrap, so the address behind those names must never change → Elastic IP.
resource "aws_eip" "zrok2" {
  domain = "vpc"
  tags   = { Name = "zrok2" }
}

resource "aws_eip_association" "zrok2" {
  instance_id   = aws_instance.zrok2.id
  allocation_id = aws_eip.zrok2.id
}

# The target "public" subnet has no explicit route table, so it inherits the VPC
# main table — which lacks a default route to the IGW (no internet egress). Give
# our subnet a real public route table so the instance can pull images, reach the
# ECS/SSM control plane, and complete ACME.
resource "aws_route_table" "public" {
  vpc_id = var.vpc_id
  tags   = { Name = "zrok2-public" }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = data.aws_internet_gateway.vpc.id
}

resource "aws_route_table_association" "zrok2" {
  subnet_id      = var.subnet_id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "zrok2" {
  name        = "zrok2"
  description = "zrok2 self-hosted stack"
  vpc_id      = var.vpc_id

  # HTTPS (Caddy: zrok2 controller API + wildcard frontend + ziti mgmt API)
  ingress {
    description = "HTTPS via Caddy"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # OpenZiti controller control plane (mTLS, direct — cannot be proxied)
  ingress {
    description = "Ziti controller control plane"
    from_port   = var.ziti_ctrl_port
    to_port     = var.ziti_ctrl_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # OpenZiti router data plane (TLS, direct — SDK clients)
  ingress {
    description = "Ziti router data plane"
    from_port   = var.ziti_router_port
    to_port     = var.ziti_router_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Optional SSH (default: closed; use SSM Session Manager instead)
  dynamic "ingress" {
    for_each = var.admin_ssh_cidr == "" ? [] : [var.admin_ssh_cidr]
    content {
      description = "SSH admin"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "zrok2" }
}

# One wildcard record covers ziti., router., zrok2., and every share subdomain.
resource "aws_route53_record" "wildcard" {
  zone_id = var.hosted_zone_id
  name    = "*.${var.dns_zone}"
  type    = "A"
  ttl     = 60
  records = [aws_eip.zrok2.public_ip]
}

resource "aws_route53_record" "apex" {
  zone_id = var.hosted_zone_id
  name    = var.dns_zone
  type    = "A"
  ttl     = 60
  records = [aws_eip.zrok2.public_ip]
}
