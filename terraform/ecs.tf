resource "aws_ecs_cluster" "zrok2" {
  name = "zrok2"

  setting {
    name  = "containerInsights"
    value = "disabled" # keep cost low
  }
}

resource "aws_cloudwatch_log_group" "zrok2" {
  name              = "/ecs/zrok2"
  retention_in_days = 14
}

locals {
  log_options = {
    "awslogs-group"         = aws_cloudwatch_log_group.zrok2.name
    "awslogs-region"        = var.region
    "awslogs-stream-prefix" = "zrok2"
  }

  ziti_pwd_arn    = aws_ssm_parameter.zrok2["ziti_pwd"].arn
  admin_token_arn = aws_ssm_parameter.zrok2["admin_token"].arn
  db_password_arn = aws_ssm_parameter.zrok2["db_password"].arn

  container_definitions = [
    # ── Ziti controller ──────────────────────────────────────────────────────
    {
      name              = "ziti-controller"
      image             = var.ziti_controller_image
      essential         = true
      memoryReservation = 256
      environment = [
        { name = "ZITI_BOOTSTRAP", value = "true" },
        { name = "ZITI_BOOTSTRAP_CLUSTER", value = "true" },
        { name = "ZITI_CTRL_ADVERTISED_ADDRESS", value = local.ziti_host },
        { name = "ZITI_CTRL_ADVERTISED_PORT", value = tostring(var.ziti_ctrl_port) },
        { name = "ZITI_USER", value = var.ziti_user },
        { name = "ZITI_CLUSTER_TRUST_DOMAIN", value = var.dns_zone },
        { name = "ZITI_CLUSTER_NODE_NAME", value = "ziti-ctrl" },
        { name = "PFXLOG_NO_JSON", value = "true" },
      ]
      secrets = [
        { name = "ZITI_PWD", valueFrom = local.ziti_pwd_arn },
      ]
      portMappings = [
        { containerPort = var.ziti_ctrl_port, hostPort = var.ziti_ctrl_port, protocol = "tcp" },
      ]
      mountPoints = [
        { sourceVolume = "ziti-ctrl-data", containerPath = "/ziti-controller", readOnly = false },
      ]
      healthCheck = {
        command     = ["CMD", "ziti", "agent", "stats"]
        interval    = 5
        timeout     = 5
        retries     = 10
        startPeriod = 30
      }
      logConfiguration = { logDriver = "awslogs", options = local.log_options }
    },

    # ── Ziti router init (one-shot) ─────────────────────────────────────────
    {
      name              = "ziti-router-init"
      image             = var.ziti_controller_image
      essential         = false
      memoryReservation = 128
      user              = "0:0" # write the router JWT into the root-owned /ziti-router volume
      entryPoint        = ["/bin/bash", "-c"]
      command           = [file("${path.module}/scripts/ziti-router-init.sh")]
      environment = [
        { name = "ZROK2_DNS_ZONE", value = var.dns_zone },
        { name = "ZITI_USER", value = var.ziti_user },
        { name = "ZITI_CTRL_PORT", value = tostring(var.ziti_ctrl_port) },
        { name = "ZITI_ROUTER_NAME", value = var.ziti_router_name },
      ]
      secrets = [
        { name = "ZITI_PWD", valueFrom = local.ziti_pwd_arn },
      ]
      dependsOn = [
        { containerName = "ziti-controller", condition = "HEALTHY" },
      ]
      links = ["ziti-controller:${local.ziti_host}"]
      mountPoints = [
        { sourceVolume = "ziti-router-data", containerPath = "/ziti-router", readOnly = false },
      ]
      logConfiguration = { logDriver = "awslogs", options = local.log_options }
    },

    # ── Ziti router ─────────────────────────────────────────────────────────
    {
      name              = "ziti-router"
      image             = var.ziti_router_image
      essential         = true
      memoryReservation = 192
      environment = [
        { name = "ZITI_BOOTSTRAP", value = "true" },
        { name = "ZITI_BOOTSTRAP_ENROLLMENT", value = "true" },
        { name = "ZITI_BOOTSTRAP_CONFIG", value = "true" },
        { name = "ZITI_AUTO_RENEW_CERTS", value = "true" },
        { name = "ZITI_CTRL_ADVERTISED_ADDRESS", value = local.ziti_host },
        { name = "ZITI_CTRL_ADVERTISED_PORT", value = tostring(var.ziti_ctrl_port) },
        { name = "ZITI_ROUTER_ADVERTISED_ADDRESS", value = local.router_host },
        { name = "ZITI_ROUTER_PORT", value = tostring(var.ziti_router_port) },
        { name = "ZITI_ROUTER_NAME", value = var.ziti_router_name },
        { name = "ZITI_ENROLL_TOKEN", value = "/ziti-router/${var.ziti_router_name}.jwt" },
        { name = "PFXLOG_NO_JSON", value = "true" },
      ]
      dependsOn = [
        { containerName = "ziti-router-init", condition = "SUCCESS" },
      ]
      links = ["ziti-controller:${local.ziti_host}"]
      mountPoints = [
        { sourceVolume = "ziti-router-data", containerPath = "/ziti-router", readOnly = false },
      ]
      portMappings = [
        { containerPort = var.ziti_router_port, hostPort = var.ziti_router_port, protocol = "tcp" },
      ]
      healthCheck = {
        command     = ["CMD", "ziti", "agent", "stats"]
        interval    = 5
        timeout     = 5
        retries     = 10
        startPeriod = 30
      }
      logConfiguration = { logDriver = "awslogs", options = local.log_options }
    },

    # ── PostgreSQL ──────────────────────────────────────────────────────────
    {
      name              = "postgresql"
      image             = var.postgres_image
      essential         = true
      memoryReservation = 256
      environment = [
        { name = "POSTGRES_USER", value = "zrok2" },
        { name = "POSTGRES_DB", value = "zrok2" },
      ]
      secrets = [
        { name = "POSTGRES_PASSWORD", valueFrom = local.db_password_arn },
      ]
      mountPoints = [
        { sourceVolume = "pg-data", containerPath = "/var/lib/postgresql/data", readOnly = false },
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "pg_isready -U zrok2"]
        interval    = 5
        timeout     = 3
        retries     = 10
        startPeriod = 10
      }
      logConfiguration = { logDriver = "awslogs", options = local.log_options }
    },

    # ── RabbitMQ (required by dynamic frontend) ─────────────────────────────
    {
      name              = "rabbitmq"
      image             = var.rabbitmq_image
      essential         = true
      memoryReservation = 256
      mountPoints = [
        { sourceVolume = "rabbitmq-data", containerPath = "/var/lib/rabbitmq", readOnly = false },
      ]
      healthCheck = {
        command     = ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
        interval    = 10
        timeout     = 5
        retries     = 10
        startPeriod = 20
      }
      logConfiguration = { logDriver = "awslogs", options = local.log_options }
    },

    # ── zrok2 bootstrap (one-shot) ──────────────────────────────────────────
    {
      name              = "zrok2-init"
      image             = var.zrok2_image
      essential         = false
      memoryReservation = 128
      user              = "0:0"
      entryPoint        = ["/bin/bash", "/bootstrap/entrypoint-init.bash"]
      environment = [
        { name = "ZROK2_DNS_ZONE", value = var.dns_zone },
        { name = "ZITI_USER", value = var.ziti_user },
        { name = "ZITI_CTRL_PORT", value = tostring(var.ziti_ctrl_port) },
        { name = "ZROK2_CTRL_PORT", value = tostring(var.zrok2_ctrl_port) },
        { name = "ZROK2_FRONTEND_PORT", value = tostring(var.zrok2_frontend_port) },
        { name = "ZROK2_STORE_TYPE", value = "postgres" },
        { name = "ZROK2_METRICS_ENABLED", value = "false" },
        { name = "ZROK2_INFLUX_TOKEN", value = "" },
        { name = "HOME", value = "/var/lib/zrok2" },
      ]
      secrets = [
        { name = "ZROK2_ADMIN_TOKEN", valueFrom = local.admin_token_arn },
        { name = "ZITI_PWD", valueFrom = local.ziti_pwd_arn },
        { name = "ZROK2_DB_PASSWORD", valueFrom = local.db_password_arn },
      ]
      dependsOn = [
        { containerName = "ziti-controller", condition = "HEALTHY" },
        { containerName = "postgresql", condition = "HEALTHY" },
        { containerName = "rabbitmq", condition = "HEALTHY" },
      ]
      links = ["ziti-controller:${local.ziti_host}", "postgresql", "rabbitmq"]
      mountPoints = [
        { sourceVolume = "zrok2-config", containerPath = "/var/lib/zrok2", readOnly = false },
        { sourceVolume = "bootstrap-entrypoint", containerPath = "/bootstrap/entrypoint-init.bash", readOnly = true },
        { sourceVolume = "bootstrap-lib", containerPath = "/bootstrap/zrok2-bootstrap.bash", readOnly = true },
      ]
      logConfiguration = { logDriver = "awslogs", options = local.log_options }
    },

    # ── zrok2 controller ────────────────────────────────────────────────────
    {
      name              = "zrok2-controller"
      image             = var.zrok2_image
      essential         = true
      memoryReservation = 192
      command           = ["controller", "/var/lib/zrok2/config/ctrl.yaml"]
      environment = [
        { name = "ZROK2_API_ENDPOINT", value = "http://127.0.0.1:${var.zrok2_ctrl_port}" },
        { name = "HOME", value = "/var/lib/zrok2" },
      ]
      secrets = [
        { name = "ZROK2_ADMIN_TOKEN", valueFrom = local.admin_token_arn },
      ]
      dependsOn = [
        { containerName = "zrok2-init", condition = "SUCCESS" },
      ]
      links = ["postgresql", "rabbitmq", "ziti-controller:${local.ziti_host}"]
      mountPoints = [
        { sourceVolume = "zrok2-config", containerPath = "/var/lib/zrok2", readOnly = false },
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "curl -sf http://127.0.0.1:${var.zrok2_ctrl_port}/api/v1/version || exit 1"]
        interval    = 5
        timeout     = 3
        retries     = 10
        startPeriod = 15
      }
      logConfiguration = { logDriver = "awslogs", options = local.log_options }
    },

    # ── zrok2 frontend (public dynamic proxy) ───────────────────────────────
    {
      name              = "zrok2-frontend"
      image             = var.zrok2_image
      essential         = true
      memoryReservation = 128
      command           = ["access", "dynamicProxy", "/var/lib/zrok2/config/frontend.yaml"]
      environment = [
        { name = "ZROK2_API_ENDPOINT", value = "http://zrok2-controller:${var.zrok2_ctrl_port}" },
        { name = "HOME", value = "/var/lib/zrok2" },
      ]
      dependsOn = [
        { containerName = "zrok2-controller", condition = "HEALTHY" },
      ]
      links = ["zrok2-controller", "rabbitmq", "ziti-controller:${local.ziti_host}", "ziti-router:${local.router_host}"]
      mountPoints = [
        { sourceVolume = "zrok2-config", containerPath = "/var/lib/zrok2", readOnly = true },
      ]
      logConfiguration = { logDriver = "awslogs", options = local.log_options }
    },

    # ── Caddy (TLS termination via Route53 DNS-01) ──────────────────────────
    {
      name              = "caddy"
      image             = local.caddy_image
      essential         = true
      memoryReservation = 128
      environment = [
        { name = "ZROK2_DNS_ZONE", value = var.dns_zone },
        { name = "ZITI_CTRL_PORT", value = tostring(var.ziti_ctrl_port) },
        { name = "ZROK2_CTRL_PORT", value = tostring(var.zrok2_ctrl_port) },
        { name = "ZROK2_FRONTEND_PORT", value = tostring(var.zrok2_frontend_port) },
        { name = "AWS_REGION", value = var.region },
        { name = "CADDY_ACME_API", value = "https://acme-v02.api.letsencrypt.org/directory" },
      ]
      dependsOn = [
        { containerName = "zrok2-controller", condition = "HEALTHY" },
      ]
      links = ["zrok2-controller", "zrok2-frontend", "ziti-controller"]
      portMappings = [
        { containerPort = 443, hostPort = 443, protocol = "tcp" },
      ]
      mountPoints = [
        { sourceVolume = "caddy-data", containerPath = "/data", readOnly = false },
        { sourceVolume = "caddy-config", containerPath = "/config", readOnly = false },
      ]
      logConfiguration = { logDriver = "awslogs", options = local.log_options }
    },
  ]
}

resource "aws_ecs_task_definition" "zrok2" {
  family             = "zrok2"
  network_mode       = "bridge"
  task_role_arn      = aws_iam_role.task.arn
  execution_role_arn = aws_iam_role.execution.arn

  requires_compatibilities = ["EC2"]

  container_definitions = jsonencode(local.container_definitions)

  # Docker-managed named volumes (mirror the compose named volumes; persist on
  # the instance across task restarts).
  dynamic "volume" {
    for_each = toset([
      "ziti-ctrl-data", "ziti-router-data", "zrok2-config",
      "pg-data", "rabbitmq-data", "caddy-data", "caddy-config",
    ])
    content {
      name = volume.value
      docker_volume_configuration {
        scope         = "shared"
        autoprovision = true
        driver        = "local"
      }
    }
  }

  # Bootstrap scripts bind-mounted from the repo cloned by instance user-data.
  volume {
    name      = "bootstrap-entrypoint"
    host_path = "/opt/zrok2/repo/docker/compose/zrok2-instance/entrypoint-init.bash"
  }
  volume {
    name      = "bootstrap-lib"
    host_path = "/opt/zrok2/repo/nfpm/zrok2-bootstrap.bash"
  }
}

resource "aws_ecs_service" "zrok2" {
  name            = "zrok2"
  cluster         = aws_ecs_cluster.zrok2.id
  task_definition = aws_ecs_task_definition.zrok2.arn
  desired_count   = 1
  launch_type     = "EC2"

  enable_execute_command = true

  # Static host ports (443/1280/3022) can't overlap, and there's one instance —
  # so stop the old task before starting the new one on redeploy.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [aws_instance.zrok2]
}
