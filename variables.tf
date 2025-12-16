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
