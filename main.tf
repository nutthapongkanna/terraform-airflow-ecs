############################################
# main.tf — Airflow on ECS Fargate (Celery)
# - ALB -> Airflow API Server (8080)
# - RDS Postgres 16
# - ElastiCache Redis
# - EFS shared: /opt/airflow (dags/logs/plugins/config)
# - Autoscaling: worker service (CPU target)
############################################

data "aws_availability_zones" "azs" {}

locals {
  name = var.project_name

  vpc_cidr = "10.10.0.0/16"

  # sanitize for resources that require lowercase/short names (ElastiCache cluster_id max 20)
  name_lc_short = substr(replace(lower(var.project_name), "/[^a-z0-9-]/", "-"), 0, 20)

  airflow_image = "apache/airflow:${var.airflow_version}"
}

# -----------------------
# VPC (Lab: public subnets)
# -----------------------
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

# -----------------------
# Security Groups
# -----------------------
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
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

  # ALB -> api-server:8080
  ingress {
    description     = "ALB to Airflow API"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # allow tasks talk to each other (airflow internal comms)
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
    description     = "NFS from ECS tasks"
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
    description     = "Postgres from ECS tasks"
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
    description     = "Redis from ECS tasks"
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

# -----------------------
# ALB -> Target Group -> Listener
# -----------------------
resource "aws_lb" "alb" {
  name_prefix        = substr(replace("${local.name}-", "/[^a-zA-Z0-9-]/", ""), 0, 6)
  load_balancer_type = "application"
  subnets            = [for s in aws_subnet.public : s.id]
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "api" {
  name_prefix = substr(replace("${local.name}-tg-", "/[^a-zA-Z0-9-]/", ""), 0, 6)
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path    = "/health"
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

# -----------------------
# EFS (shared airflow folders)
# -----------------------
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

# -----------------------
# RDS Postgres 16 (lab)
# -----------------------
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

  username               = "airflow"
  password               = random_password.postgres.result
  db_name                = "airflow"

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.rds.name

  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = {
    Name = "${local.name}-postgres"
  }
}

# -----------------------
# ElastiCache Redis (lab)
# -----------------------
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name}-redis-subnets"
  subnet_ids = [for s in aws_subnet.public : s.id]
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.name_lc_short}-redis"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  port                 = 6379

  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]
}

# -----------------------
# ECS Cluster + Logs + IAM
# -----------------------
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
  role       = aws_iam_role.exec.name
  policy_arn  = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${local.name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_tasks.json
}

# -----------------------
# Airflow environment (CeleryExecutor)
# -----------------------
locals {
  sql_alchemy_conn = "postgresql+psycopg2://airflow:${random_password.postgres.result}@${aws_db_instance.postgres.address}:5432/airflow"
  redis_broker     = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379/0"

  airflow_env = [
    {
      name  = "AIRFLOW__CORE__EXECUTOR"
      value = "CeleryExecutor"
    },
    {
      name  = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN"
      value = local.sql_alchemy_conn
    },
    {
      name  = "AIRFLOW__CELERY__BROKER_URL"
      value = local.redis_broker
    },
    {
      name  = "AIRFLOW__CELERY__RESULT_BACKEND"
      value = "db+postgresql://airflow:${random_password.postgres.result}@${aws_db_instance.postgres.address}:5432/airflow"
    },
    {
      name  = "AIRFLOW__CORE__FERNET_KEY"
      value = random_password.fernet.result
    },
    {
      name  = "AIRFLOW__WEBSERVER__SECRET_KEY"
      value = random_password.web_secret.result
    },

    # EFS mount paths
    {
      name  = "AIRFLOW__CORE__DAGS_FOLDER"
      value = "/opt/airflow/dags"
    },
    {
      name  = "AIRFLOW__LOGGING__BASE_LOG_FOLDER"
      value = "/opt/airflow/logs"
    },
    {
      name  = "AIRFLOW__CORE__PLUGINS_FOLDER"
      value = "/opt/airflow/plugins"
    },

    # admin user creation inputs
    {
      name  = "_AIRFLOW_WWW_USER_USERNAME"
      value = var.admin_username
    },
    {
      name  = "_AIRFLOW_WWW_USER_PASSWORD"
      value = random_password.admin.result
    },
    {
      name  = "_AIRFLOW_WWW_USER_EMAIL"
      value = var.admin_email
    },
    {
      name  = "_AIRFLOW_WWW_USER_FIRSTNAME"
      value = "Admin"
    },
    {
      name  = "_AIRFLOW_WWW_USER_LASTNAME"
      value = "User"
    }
  ]
}

# Common volume + mount (EFS -> /opt/airflow)
locals {
  efs_mount = {
    sourceVolume  = "airflow-efs"
    containerPath = "/opt/airflow"
    readOnly      = false
  }
}

# -----------------------
# Task Definitions (api/scheduler/dagproc/triggerer/worker)
# -----------------------
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

      portMappings = [
        {
          containerPort = 8793
          hostPort      = 8793
          protocol      = "tcp"
        }
      ]

      environment = local.airflow_env
      command     = ["bash", "-lc", "airflow db check-migrations --timeout 180 && exec airflow scheduler"]

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

      portMappings = [
        {
          containerPort = 8794
          hostPort      = 8794
          protocol      = "tcp"
        }
      ]

      environment = local.airflow_env
      command     = ["bash", "-lc", "airflow db check-migrations --timeout 180 && exec airflow dag-processor"]

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

      portMappings = [
        {
          containerPort = 8795
          hostPort      = 8795
          protocol      = "tcp"
        }
      ]

      environment = local.airflow_env
      command     = ["bash", "-lc", "airflow db check-migrations --timeout 180 && exec airflow triggerer"]

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

      portMappings = [
        {
          containerPort = 8796
          hostPort      = 8796
          protocol      = "tcp"
        }
      ]

      environment = local.airflow_env
      command     = ["bash", "-lc", "airflow db check-migrations --timeout 180 && exec airflow celery worker"]

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

# -----------------------
# ECS Services
# -----------------------
resource "aws_ecs_service" "api" {
  name            = "${local.name}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

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

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_service.api]
}

# -----------------------
# Autoscaling for worker service (by CPU)
# -----------------------
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
