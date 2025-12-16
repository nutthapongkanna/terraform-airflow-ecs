locals {
  name     = var.project_name
  vpc_cidr = "10.10.0.0/16"

  airflow_image = "apache/airflow:${var.airflow_version}"

  alb_prefix = substr(regexreplace(lower(var.project_name), "[^a-z0-9]", ""), 0, 6)
  tg_prefix  = substr(regexreplace(lower(var.project_name), "[^a-z0-9]", ""), 0, 6)

  redis_id_base    = substr(regexreplace(lower(var.project_name), "[^a-z0-9]", ""), 0, 14)
  redis_cluster_id = "${local.redis_id_base}-redis"

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
