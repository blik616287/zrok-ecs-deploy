# ── EC2 container-instance role ──────────────────────────────────────────────
resource "aws_iam_role" "instance" {
  name               = "zrok2-ecsInstanceRole"
  assume_role_policy = file("${path.module}/../iam/ec2-trust.json")
}

resource "aws_iam_role_policy_attachment" "instance_ecs" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "instance_eip" {
  name   = "eip-associate"
  role   = aws_iam_role.instance.name
  policy = file("${path.module}/../iam/instance-eip-inline.json")
}

resource "aws_iam_instance_profile" "instance" {
  name = "zrok2-ecsInstanceProfile"
  role = aws_iam_role.instance.name
}

# ── ECS task execution role (image pulls, log writes, secret decryption) ─────
resource "aws_iam_role" "execution" {
  name               = "zrok2-ecsTaskExecutionRole"
  assume_role_policy = file("${path.module}/../iam/ecs-tasks-trust.json")
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_ssm" {
  name = "read-zrok2-secrets"
  role = aws_iam_role.execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadZrok2Secrets"
        Effect   = "Allow"
        Action   = ["ssm:GetParameters", "ssm:GetParameter", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:${var.region}:${local.account_id}:parameter/zrok2/*"
      },
      {
        Sid       = "DecryptSecureString"
        Effect    = "Allow"
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${var.region}.amazonaws.com" } }
      },
    ]
  })
}

# ── ECS task role (Caddy Route53 DNS-01 + ECS Exec) ─────────────────────────
resource "aws_iam_role" "task" {
  name               = "zrok2-taskRole"
  assume_role_policy = file("${path.module}/../iam/ecs-tasks-trust.json")
}

resource "aws_iam_role_policy" "task_route53" {
  name = "route53-and-exec"
  role = aws_iam_role.task.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Route53DnsChallenge"
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListHostedZonesByName", "route53:GetChange"]
        Resource = "*"
      },
      {
        Sid      = "Route53ChangeRecords"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/${var.hosted_zone_id}"
      },
      {
        Sid    = "EcsExecMessages"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      },
    ]
  })
}
