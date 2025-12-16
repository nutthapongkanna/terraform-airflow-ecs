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
