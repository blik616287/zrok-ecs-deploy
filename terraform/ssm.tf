# SecureString parameters. Real values already exist in SSM (created out-of-band
# with strong random values); Terraform manages the resource but ignores the
# value so it never overwrites the live secret.

locals {
  ssm_params = {
    ziti_pwd    = "/zrok2/ZITI_PWD"
    admin_token = "/zrok2/ZROK2_ADMIN_TOKEN"
    db_password = "/zrok2/ZROK2_DB_PASSWORD"
    acct_user   = "/zrok2/account/username"
    acct_pass   = "/zrok2/account/password"
  }
}

resource "aws_ssm_parameter" "zrok2" {
  for_each = local.ssm_params

  name  = each.value
  type  = "SecureString"
  value = var.ssm_placeholder

  lifecycle {
    ignore_changes = [value]
  }
}
