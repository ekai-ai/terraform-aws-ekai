resource "aws_security_group" "rds_sg" {
  name        = "${var.env}-rds-postgresql-sg"
  description = "Allow inbound traffic to PostgreSQL ${var.env}"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow PostgreSQL access from within the VPC only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.env}-rds-postgresql-sg"
    managed = "Terraform"
  }
}
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${var.env}-rds-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name    = "${var.env}-rds-subnet-group"
    managed = "Terraform"
  }

}
# Data source to retrieve the secret — skipped entirely for self_service,
# which generates its own credentials below instead of requiring a
# pre-existing secret.
data "aws_secretsmanager_secret_version" "ekai-db" {
  count     = var.self_service ? 0 : 1
  secret_id = var.secrets_name
}

# self_service only — no pre-existing secret to read DB credentials from.
resource "random_password" "backend_db" {
  count   = var.self_service ? 1 : 0
  length  = 24
  special = false
}

resource "random_password" "semantics_db" {
  count   = var.self_service ? 1 : 0
  length  = 24
  special = false
}

locals {
  backend_db_username   = var.self_service ? "ekai_backend" : jsondecode(data.aws_secretsmanager_secret_version.ekai-db[0].secret_string)["backend_db_username"]
  backend_db_password   = var.self_service ? random_password.backend_db[0].result : jsondecode(data.aws_secretsmanager_secret_version.ekai-db[0].secret_string)["backend_db_password"]
  backend_db_name       = var.self_service ? "ekai_backend" : jsondecode(data.aws_secretsmanager_secret_version.ekai-db[0].secret_string)["backend_db_name"]
  semantics_db_name     = var.self_service ? "ekai_semantics" : jsondecode(data.aws_secretsmanager_secret_version.ekai-db[0].secret_string)["semantics_db_name"]
  semantics_db_username = var.self_service ? "ekai_semantics" : jsondecode(data.aws_secretsmanager_secret_version.ekai-db[0].secret_string)["semantics_db_username"]
  semantics_db_password = var.self_service ? random_password.semantics_db[0].result : jsondecode(data.aws_secretsmanager_secret_version.ekai-db[0].secret_string)["semantics_db_password"]
}
resource "aws_db_instance" "ekai_postgresql" {
  allocated_storage   = var.allocated_storage
  engine              = "postgres"
  engine_version      = var.engine_version
  db_name             = local.backend_db_name
  instance_class      = var.db_instance_class
  username            = local.backend_db_username
  password            = local.backend_db_password
  port                = "5432"
  multi_az            = var.multi_az
  identifier          = "${var.env}-ekai-saas-db"
  publicly_accessible = "false"
  # AWS's own default parameter group naming convention is "default.postgres<major>"
  # -- derived from engine_version instead of a second hardcoded literal that
  # would silently mismatch if engine_version ever moves to a new major version.
  parameter_group_name    = "default.postgres${split(".", var.engine_version)[0]}"
  storage_type            = var.storage_type
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet_group.name
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = true # No final snapshot needed

  tags = {
    Name    = "${var.env}-ekai-saas"
    managed = "terraform"

  }
}
