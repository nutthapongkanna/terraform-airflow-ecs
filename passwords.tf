resource "random_password" "postgres" {
  length  = var.password_length
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "random_password" "admin" {
  length  = var.password_length
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# Airflow secrets (อนุญาต special ได้)
resource "random_password" "fernet" {
  length  = 32
  special = true
}

resource "random_password" "web_secret" {
  length  = 32
  special = true
}
