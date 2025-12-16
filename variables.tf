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
  default = "3.1.5"
}

variable "admin_username" {
  type    = string
  default = "admin"
}

variable "admin_email" {
  type    = string
  default = "admin@example.com"
}

variable "password_length" {
  type    = number
  default = 24
}

variable "allowed_http_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

# Worker autoscaling
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

# Fargate sizes
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

# RDS/Redis sizes (lab)
variable "postgres_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}
