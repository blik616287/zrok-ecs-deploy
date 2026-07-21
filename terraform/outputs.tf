output "public_ip" {
  value = aws_eip.zrok2.public_ip
}

output "zrok2_api_endpoint" {
  value = "https://zrok2.${var.dns_zone}"
}

output "frontend_wildcard" {
  value = "*.${var.dns_zone}"
}

output "instance_id" {
  value = aws_instance.zrok2.id
}

output "cluster_name" {
  value = aws_ecs_cluster.zrok2.name
}

output "ecs_exec_bootstrap_hint" {
  description = "Create the first account after the task is healthy."
  value       = "aws ecs execute-command --profile ${var.profile} --region ${var.region} --cluster ${aws_ecs_cluster.zrok2.name} --task <TASK_ID> --container zrok2-controller --interactive --command \"zrok2 admin create account <email> <password>\""
}
