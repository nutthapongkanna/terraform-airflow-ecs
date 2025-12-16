resource "aws_efs_file_system" "airflow" {
  encrypted = true
  tags      = { Name = "${local.name}-efs" }
}

resource "aws_efs_mount_target" "mt" {
  count           = 2
  file_system_id  = aws_efs_file_system.airflow.id
  subnet_id       = aws_subnet.public[count.index].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "airflow" {
  file_system_id = aws_efs_file_system.airflow.id

  root_directory {
    path = "/airflow"
    creation_info {
      owner_uid   = 50000
      owner_gid   = 0
      permissions = "0775"
    }
  }

  posix_user {
    uid = 50000
    gid = 0
  }
}
