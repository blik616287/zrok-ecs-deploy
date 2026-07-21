resource "aws_instance" "zrok2" {
  ami                         = nonsensitive(data.aws_ssm_parameter.ecs_ami.value)
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.zrok2.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    cluster_name = aws_ecs_cluster.zrok2.name
  })
  # Replace the instance when user-data changes so it actually re-runs on boot.
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Ensure internet egress exists before the instance boots and runs user-data.
  depends_on = [aws_route_table_association.zrok2]

  tags = { Name = "zrok2" }
}
