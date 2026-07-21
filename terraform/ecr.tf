resource "aws_ecr_repository" "caddy" {
  name                 = "zrok2/caddy-route53"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # allow `terraform destroy` to remove the repo even with images

  image_scanning_configuration {
    scan_on_push = false
  }
}
