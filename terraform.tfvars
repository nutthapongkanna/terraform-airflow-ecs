aws_region   = "ap-southeast-7"
project_name = "airflow-ecs"

airflow_version = "3.1.5"

admin_username = "admin"
admin_email    = "admin@example.com"

password_length = 24

allowed_http_cidrs = ["0.0.0.0/0"]

worker_min        = 2
worker_max        = 10
worker_cpu_target = 60

api_cpu = 512
api_mem = 1024

sched_cpu = 512
sched_mem = 1024

dagp_cpu = 512
dagp_mem = 1024

trig_cpu = 256
trig_mem = 512

worker_cpu = 1024
worker_mem = 2048

redis_node_type          = "cache.t3.micro"
postgres_instance_class  = "db.t3.micro"
