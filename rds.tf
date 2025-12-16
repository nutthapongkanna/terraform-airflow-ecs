resource "aws_db_subnet_group" "rds" {
  name       = "${local.name}-rds-subnets"
  subnet_ids = [for s in aws_subnet.public : s.id]
}

resource "aws_db_instance" "postgres" {
  identifier        = "${local.name}-pg"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.postgres_instance_class
  allocated_storage = 20
  storage_type      = "gp3"

  storage_encrypted = true

  username = "airflow"
  password = random_password.postgres.result
  db_name  = "airflow"

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.rds.name

  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false

  tags = { Name = "${local.name}-postgres" }
}
