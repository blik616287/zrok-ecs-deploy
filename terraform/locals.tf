locals {
  account_id  = data.aws_caller_identity.current.account_id
  registry    = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  caddy_image = "${local.registry}/zrok2/caddy-route53:latest"

  # Ziti advertised hostnames (also public via the wildcard DNS record).
  ziti_host   = "ziti.${var.dns_zone}"
  router_host = "router.${var.dns_zone}"
}
