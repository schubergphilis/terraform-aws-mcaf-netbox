locals {
  ssm_prefix = "${var.name}/netbox"

  environment = {
    "ALLOWED_HOSTS"         = "*"
    "AWS_REGION"            = data.aws_region.current.name,
    "CORS_ORIGIN_ALLOW_ALL" = "true"
    "DB_HOST"               = var.aurora_endpoint
    "DB_NAME"               = "netbox"
    "DB_PASSWORD"           = "ssm://${aws_ssm_parameter.aurora_password.name}"
    "DB_PORT"               = var.aurora_port
    "DB_USER"               = "netbox"
    "DEBUG"                 = "true"
    "LOGIN_REQUIRED"        = "true"
    "MAIL_FROM"             = var.email
    "MAX_PAGE_SIZE"         = "1000"
    "PAGINATE_COUNT"        = "100"
    "PREFER_IPV4"           = "true"
    "REDIS_HOST"            = aws_elasticache_cluster.default.cache_nodes.0.address
    "REDIS_PORT"            = aws_elasticache_cluster.default.cache_nodes.0.port
    "REDIS_SSL"             = "false"
    "SECRET_KEY"            = "ssm://${aws_ssm_parameter.secret_key.name}"
    "SUPERUSER_API_TOKEN"   = "ssm://${aws_ssm_parameter.api_token.name}"
    "SUPERUSER_EMAIL"       = var.email
    "SUPERUSER_NAME"        = "admin"
    "SUPERUSER_PASSWORD"    = "ssm://${aws_ssm_parameter.superuser_password.name}"
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "task_execution_role" {
  statement {
    actions = [
      "kms:Decrypt"
    ]
    resources = [
      var.kms_key_arn
    ]
  }

  statement {
    actions = [
      "ssm:GetParameter"
    ]
    resources = [
      "arn:aws:ssm:*:*:parameter/${local.ssm_prefix}/*",
    ]
  }

  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      "arn:aws:secretsmanager:*:*:secret:/${local.ssm_prefix}/*",
    ]
  }
}

module "task_execution_role" {
  source = "github.com/schubergphilis/terraform-aws-mcaf-role?ref=v0.3.0"

  create_policy         = true
  name                  = "TaskExecution-${var.name}-netbox-"
  principal_identifiers = ["ecs-tasks.amazonaws.com"]
  principal_type        = "Service"
  role_policy           = data.aws_iam_policy_document.task_execution_role.json
  tags                  = var.tags
}

resource "aws_iam_role_policy_attachment" "task_execution_role" {
  role       = module.task_execution_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "random_password" "superuser_password" {
  length  = 16
  special = false
}

resource "random_password" "aurora_password" {
  length  = 16
  special = false
}

resource "random_password" "api_token" {
  length  = 16
  special = false
}

resource "random_password" "secret_key" {
  length           = 16
  special          = true
  override_special = "!@#$%^&*(-_=+)"
}

resource "aws_cloudwatch_log_group" "default" {
  name              = "/ecs/${var.name}"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_security_group" "ecs" {
  name        = "${var.name}-netbox-ecs"
  description = "Allow inbound access from the ALB only"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress {
    protocol        = "tcp"
    from_port       = 8001
    to_port         = 8001
    security_groups = concat([aws_security_group.alb.id], var.allowed_security_group_ids)
  }

  ingress {
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = concat([aws_security_group.alb.id], var.allowed_security_group_ids)
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "default" {
  name = "${var.name}-netbox"
  tags = var.tags
}

data "null_data_source" "environment" {
  count = length(local.environment)

  inputs = {
    name  = keys(local.environment)[count.index]
    value = values(local.environment)[count.index]
  }
}

resource "aws_ecs_task_definition" "default" {
  family                   = "${var.name}-netbox"
  execution_role_arn       = module.task_execution_role.arn
  task_role_arn            = module.task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  tags                     = var.tags

  container_definitions = jsonencode([
    {
      name        = "${var.name}-netbox-app"
      image       = "docker.pkg.github.com/schubergphilis/netbox-docker/netbox-app:${var.netbox_version}"
      cpu         = 512
      memory      = 1024
      networkMode = "awsvpc",
      command     = ["gunicorn", "-c /etc/netbox/config/gunicorn_config.py", "netbox.wsgi"]
      environment = data.null_data_source.environment.*.outputs

      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.repository_credentials.arn
      }

      logConfiguration = {
        logDriver = "awslogs",

        options = {
          awslogs-group         = aws_cloudwatch_log_group.default.name,
          awslogs-region        = data.aws_region.current.name,
          awslogs-stream-prefix = "ecs"
        }
      }

      portMappings = [
        {
          containerPort = 8001
          hostPort      = 8001
        }
      ]
    },
    {
      name        = "${var.name}-netbox-nginx"
      image       = "docker.pkg.github.com/schubergphilis/netbox-docker/netbox-nginx:${var.netbox_version}"
      cpu         = 512
      memory      = 1024
      networkMode = "awsvpc",

      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.repository_credentials.arn
      }

      logConfiguration = {
        logDriver = "awslogs",

        options = {
          awslogs-group         = aws_cloudwatch_log_group.default.name,
          awslogs-region        = data.aws_region.current.name,
          awslogs-stream-prefix = "ecs"
        }
      }

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "default" {
  name            = "${var.name}-netbox"
  cluster         = aws_ecs_cluster.default.id
  task_definition = aws_ecs_task_definition.default.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = concat([aws_security_group.ecs.id], var.allowed_security_group_ids)
    subnets          = var.private_subnet_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.app.id
    container_name   = "${var.name}-netbox-app"
    container_port   = 8001
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.nginx.id
    container_name   = "${var.name}-netbox-nginx"
    container_port   = 8080
  }

  depends_on = [aws_alb_listener.https]
}

resource "aws_ssm_parameter" "secret_key" {
  name   = "/${local.ssm_prefix}/secret_key"
  type   = "SecureString"
  value  = random_password.secret_key.result
  key_id = var.kms_key_arn
  tags   = var.tags
}

resource "aws_ssm_parameter" "api_token" {
  name   = "/${local.ssm_prefix}/api_token"
  type   = "SecureString"
  value  = random_password.api_token.result
  key_id = var.kms_key_arn
  tags   = var.tags
}

resource "aws_secretsmanager_secret" "repository_credentials" {
  name       = "/${local.ssm_prefix}/repository_credentials"
  kms_key_id = var.kms_key_arn
  tags       = var.tags
}

resource "aws_secretsmanager_secret_version" "repository_credentials" {
  secret_id     = aws_secretsmanager_secret.repository_credentials.id
  secret_string = <<EOF
{
  "username" : "${var.repository_credentials_username}",
  "password" : "${var.repository_credentials_password}"
}
EOF
}

resource "aws_ssm_parameter" "superuser_password" {
  name   = "/${local.ssm_prefix}/superuser_password"
  type   = "SecureString"
  value  = random_password.superuser_password.result
  key_id = var.kms_key_arn
  tags   = var.tags
}

resource "aws_ssm_parameter" "aurora_password" {
  name   = "/${local.ssm_prefix}/aurora_password"
  type   = "SecureString"
  value  = random_password.aurora_password.result
  key_id = var.kms_key_arn
  tags   = var.tags
}
