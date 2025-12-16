variable "aws_region" {
  type    = string
  default = "ap-southeast-7" # Thailand
}

variable "project_name" {
  type    = string
  default = "airflow-ecs"
}

# Airflow image tag
variable "airflow_version" {
  type    = string
  default = "3.1.5"
}

# Admin user (password gen โดย random_password)
variable "admin_username" {
  type    = string
  default = "admin"
}

variable "admin_email" {
  type    = string
  default = "admin@example.com"
}

# Password length (no special chars สำหรับ admin + postgres)
variable "password_length" {
  type    = number
  default = 24
}

# เปิดหน้าเว็บ ALB (HTTP/80)
variable "allowed_http_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

# Worker autoscaling (ECS Service Auto Scaling)
variable "worker_min" {
  type    = number
  default = 1
}

variable "worker_max" {
  type    = number
  default = 5
}

variable "worker_cpu_target" {
  type    = number
  default = 60
}

# Fargate sizing (เริ่มต้น)
variable "api_cpu"   { type = number, default = 512 }
variable "api_mem"   { type = number, default = 1024 }

variable "sched_cpu" { type = number, default = 512 }
variable "sched_mem" { type = number, default = 1024 }

variable "dagp_cpu"  { type = number, default = 512 }
variable "dagp_mem"  { type = number, default = 1024 }

variable "trig_cpu"  { type = number, default = 256 }
variable "trig_mem"  { type = number, default = 512 }

variable "worker_cpu" { type = number, default = 1024 }
variable "worker_mem" { type = number, default = 2048 }

# Redis (ElastiCache) sizing
variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}

# RDS Postgres sizing
variable "postgres_instance_class" {
  type    = string
  default = "db.t3.micro"
}
