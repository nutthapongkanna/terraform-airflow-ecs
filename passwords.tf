resource "random_password" "postgres" {
  length  = var.password_length
  special = false
}

resource "random_password" "admin" {
  length  = var.password_length
  special = false
}

resource "random_password" "fernet" {
  length  = 32
  special = false
}

resource "random_password" "web_secret" {
  length  = 32
  special = true
}
