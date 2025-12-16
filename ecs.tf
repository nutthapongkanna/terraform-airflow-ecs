resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"
}

resource "aws_cloudwatch_log_group" "lg" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7
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
  name                   = "${local.name}-scheduler"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.scheduler.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_service.api]
}

resource "aws_ecs_service" "dagproc" {
  name                   = "${local.name}-dagproc"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.dagproc.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_service.api]
}

resource "aws_ecs_service" "triggerer" {
  name                   = "${local.name}-triggerer"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.triggerer.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = [for s in aws_subnet.public : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_service.api]
}

resource "aws_ecs_service" "worker" {
  name                   = "${local.name}-worker"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.worker.arn
  desired_count          = var.worker_min
  launch_type            = "FARGATE"
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
