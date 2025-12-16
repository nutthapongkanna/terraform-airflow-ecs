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
