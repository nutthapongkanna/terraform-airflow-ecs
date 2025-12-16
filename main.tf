terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "azs" {}

variable "aws_region" {
  type    = string
  default = "ap-southeast-7"
}

variable "project_name" {
  type    = string
  default = "airflow-ecs"
}

variable "airflow_version" {
  type    = string
  default = "3.0.2"
}

variable "allowed_http_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "admin_username" {
  type    = string
  default = "admin"
}

variable "admin_email" {
  type    = string
  default = "admin@example.com"
}

variable "postgres_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "redis_node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "api_cpu" {
  type    = number
  default = 512
}

variable "api_mem" {
  type    = number
  default = 1024
}

variable "sched_cpu" {
  type    = number
  default = 512
}

variable "sched_mem" {
  type    = number
  default = 1024
}

variable "dagp_cpu" {
  type    = number
  default = 512
}

variable "dagp_mem" {
  type    = number
  default = 1024
}

variable "trig_cpu" {
  type    = number
  default = 256
}

variable "trig_mem" {
  type    = number
  default = 512
}

variable "worker_cpu" {
  type    = number
  default = 1024
}

variable "worker_mem" {
  type    = number
  default = 2048
}

variable "worker_min" {
  type    = number
  default = 2
}

variable "worker_max" {
  type    = number
  default = 4
}

variable "worker_cpu_target" {
  type    = number
  default = 60
}

resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "random_password" "fernet" {
  length  = 32
  special = false
}

resource "random_password" "web_secret" {
  length  = 32
  special = true
}

locals {
  name     = var.project_name
  vpc_cidr = "10.10.0.0/16"

  airflow_image = "apache/airflow:${var.airflow_version}"

  alb_prefix = substr(replace(lower(var.project_name), "/[^a-z0-9]/", ""), 0, 6)
  tg_prefix  = substr(replace(lower(var.project_name), "/[^a-z0-9]/", ""), 0, 6)

  redis_id_base     = substr(replace(lower(var.project_name), "/[^a-z0-9]/", ""), 0, 14)
  redis_cluster_id  = "${local.redis_id_base}-redis"

  sql_alchemy_conn = "postgresql+psycopg2://airflow:${random_password.postgres.result}@${aws_db_instance.postgres.address}:5432/airflow"
  redis_broker     = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379/0"

  airflow_env = [
    { name = "AIRFLOW__CORE__EXECUTOR", value = "CeleryExecutor" },
    { name = "AIRFLOW__CORE__AUTH_MANAGER", value = "airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager" },
    { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = local.sql_alchemy_conn },
    { name = "AIRFLOW__CELERY__BROKER_URL", value = local.redis_broker },
    { name = "AIRFLOW__CELERY__RESULT_BACKEND", value = "db+postgresql://airflow:${random_password.postgres.result}@${aws_db_instance.postgres.address}:5432/airflow" },
    { name = "AIRFLOW__CORE__FERNET_KEY", value = random_password.fernet.result },
    { name = "AIRFLOW__WEBSERVER__SECRET_KEY", value = random_password.web_secret.result },
    { name = "AIRFLOW__CORE__DAGS_FOLDER", value = "/opt/airflow/dags" },
    { name = "AIRFLOW__LOGGING__BASE_LOG_FOLDER", value = "/opt/airflow/logs" },
    { name = "AIRFLOW__CORE__PLUGINS_FOLDER", value = "/opt/airflow/plugins" },
    { name = "_AIRFLOW_WWW_USER_USERNAME", value = var.admin_username },
    { name = "_AIRFLOW_WWW_USER_PASSWORD", value = random_password.admin.result },
    { name = "_AIRFLOW_WWW_USER_EMAIL", value = var.admin_email },
    { name = "_AIRFLOW_WWW_USER_FIRSTNAME", value = "Admin" },
    { name = "_AIRFLOW_WWW_USER_LASTNAME", value = "User" }
  ]

  efs_mount = {
    sourceVolume  = "airflow-efs"
    containerPath = "/opt/airflow"
    readOnly      = false
  }
}

resource "aws_vpc" "this" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(local.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.azs.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.name}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-alb-sg"
  }
}

resource "aws_security_group" "tasks" {
  name        = "${local.name}-tasks-sg"
  description = "ECS Tasks SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-tasks-sg"
  }
}

resource "aws_security_group" "efs" {
  name        = "${local.name}-efs-sg"
  description = "EFS SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-efs-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "RDS SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-rds-sg"
  }
}

resource "aws_security_group" "redis" {
  name        = "${local.name}-redis-sg"
  description = "Redis SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-redis-sg"
  }
}

resource "aws_lb" "alb" {
  name_prefix        = local.alb_prefix
  load_balancer_type = "application"
  subnets            = [for s in aws_subnet.public : s.id]
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "api" {
  name_prefix = local.tg_prefix
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path    = "/api/v1/health"
    matcher = "200-399"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_efs_file_system" "airflow" {
  encrypted = true

  tags = {
    Name = "${local.name}-efs"
  }
}

resource "aws_efs_mount_target" "mt" {
  count           = 2
  file_system_id  = aws_efs_file_system.airflow.id
  subnet_id       = aws_subnet.public[count.index].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "airflow" {
  file_system_id = aws_efs_file_system.airflow.id

  root_directory {
    path = "/airflow"
    creation_info {
      owner_uid   = 50000
      owner_gid   = 0
      permissions = "0775"
    }
  }

  posix_user {
    uid = 50000
    gid = 0
  }
}

resource "aws_db_subnet_group" "rds" {
  name       = "${local.name}-rds-subnets"
  subnet_ids = [for s in aws_subnet.public : s.id]
}

resource "aws_db_instance" "postgres" {
  identifier             = "${local.name}-pg"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.postgres_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true

  username = "airflow"
  password = random_password.postgres.result
  db_name  = "airflow"

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.rds.name

  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "${local.name}-postgres"
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name}-redis-subnets"
  subnet_ids = [for s in aws_subnet.public : s.id]
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id         = local.redis_cluster_id
  engine             = "redis"
  engine_version     = "7.0"
  node_type          = var.redis_node_type
  num_cache_nodes    = 1
  port               = 6379
  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"
}

resource "aws_cloudwatch_log_group" "lg" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7
}

data "aws_iam_policy_document" "assume_ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "exec" {
  name               = "${local.name}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_tasks.json
}

resource "aws_iam_role_policy_attachment" "exec_attach" {
  role      = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${local.name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_tasks.json
}

resource "aws_iam_role_policy" "ecs_exec_ssm" {
  name = "${local.name}-ecs-exec-ssm"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.api_cpu)
  memory                   = tostring(var.api_mem)
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = aws_iam_role.task.arn

  volume {
    name = "airflow-efs"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.airflow.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.airflow.id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = local.airflow_image
      essential = true

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      environment = local.airflow_env

      command = [
        "bash",
        "-lc",
        "airflow db migrate && airflow users create --role Admin --username \"$${_AIRFLOW_WWW_USER_USERNAME}\" --password \"$${_AIRFLOW_WWW_USER_PASSWORD}\" --firstname \"$${_AIRFLOW_WWW_USER_FIRSTNAME}\" --lastname \"$${_AIRFLOW_WWW_USER_LASTNAME}\" --email \"$${_AIRFLOW_WWW_USER_EMAIL}\" || true; exec airflow api-server"
      ]

      mountPoints = [local.efs_mount]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.lg.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "scheduler" {
  family                   = "${local.name}-scheduler"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.sched_cpu)
  memory                   = tostring(var.sched_mem)
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = aws_iam_role.task.arn

  volume {
    name = "airflow-efs"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.airflow.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.airflow.id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "scheduler"
      image     = local.airflow_image
      essential = true

      environment = local.airflow_env
      command = [
        "bash",
        "-lc",
        "until airflow db check-migrations; do echo waiting for db...; sleep 10; done; exec airflow scheduler"
      ]

      mountPoints = [local.efs_mount]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.lg.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "scheduler"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "dagproc" {
  family                   = "${local.name}-dagproc"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.dagp_cpu)
  memory                   = tostring(var.dagp_mem)
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = aws_iam_role.task.arn

  volume {
    name = "airflow-efs"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.airflow.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.airflow.id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "dagproc"
      image     = local.airflow_image
      essential = true

      environment = local.airflow_env
      command = [
        "bash",
        "-lc",
        "until airflow db check-migrations; do echo waiting for db...; sleep 10; done; exec airflow dag-processor"
      ]

      mountPoints = [local.efs_mount]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.lg.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "dagproc"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "triggerer" {
  family                   = "${local.name}-triggerer"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.trig_cpu)
  memory                   = tostring(var.trig_mem)
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = aws_iam_role.task.arn

  volume {
    name = "airflow-efs"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.airflow.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.airflow.id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "triggerer"
      image     = local.airflow_image
      essential = true

      environment = local.airflow_env
      command = [
        "bash",
        "-lc",
        "until airflow db check-migrations; do echo waiting for db...; sleep 10; done; exec airflow triggerer"
      ]

      mountPoints = [local.efs_mount]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.lg.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "triggerer"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${local.name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.worker_cpu)
  memory                   = tostring(var.worker_mem)
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = aws_iam_role.task.arn

  volume {
    name = "airflow-efs"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.airflow.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.airflow.id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = local.airflow_image
      essential = true

      environment = local.airflow_env
      command = [
        "bash",
        "-lc",
        "until airflow db check-migrations; do echo waiting for db...; sleep 10; done; exec airflow celery worker"
      ]

      mountPoints = [local.efs_mount]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.lg.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "worker"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "api" {
  name                   = "${local.name}-api"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.api.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true

  health_check_grace_period_seconds = 180

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8080
  }

  depends_on = [
    aws_lb_listener.http,
    aws_efs_mount_target.mt,
    aws_db_instance.postgres,
    aws_elasticache_cluster.redis
  ]
}

resource "aws_ecs_service" "scheduler" {
  name            = "${local.name}-scheduler"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.scheduler.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_service.api]
}

resource "aws_ecs_service" "dagproc" {
  name            = "${local.name}-dagproc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.dagproc.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_service.api]
}

resource "aws_ecs_service" "triggerer" {
  name            = "${local.name}-triggerer"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.triggerer.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_service.api]
}

resource "aws_ecs_service" "worker" {
  name            = "${local.name}-worker"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_min
  launch_type     = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_service.api]
}

resource "aws_appautoscaling_target" "worker" {
  max_capacity       = var.worker_max
  min_capacity       = var.worker_min
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "worker_cpu" {
  name               = "${local.name}-worker-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = var.worker_cpu_target
  }
}

output "admin_username" {
  value = var.admin_username
}

output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}

output "airflow_url" {
  value = "http://${aws_lb.alb.dns_name}/"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "log_group" {
  value = aws_cloudwatch_log_group.lg.name
}

output "postgres_endpoint" {
  value = aws_db_instance.postgres.address
}

output "redis_endpoint" {
  value = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "efs_id" {
  value = aws_efs_file_system.airflow.id
}

