output "airflow_url" {
  value = "http://${aws_lb.alb.dns_name}/"
}

output "admin_username" {
  value = var.admin_username
}

output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}
