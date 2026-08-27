variable "vpc_id" {
  description = "VPC ID where RDS will be deployed"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block used to restrict RDS security group ingress to internal traffic only"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the RDS subnet group"
  type        = list(string)
}

variable "db_instance_class" {
  description = "RDS instance class (e.g., db.t3.medium)"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version. AWS periodically drops old minor versions from the supported list (aws rds describe-db-engine-versions --engine postgres) -- a hardcoded value here will eventually 404 on a fresh apply, so this must flow from tfvars."
  type        = string
}

variable "storage_type" {
  description = "RDS storage type (gp2, gp3, io1, ...)."
  type        = string
  default     = "gp2"
}

variable "allocated_storage" {
  description = "Allocated storage in GB for the RDS instance"
  type        = number
}

variable "backup_retention_period" {
  description = "Number of days to retain automated RDS backups (0 disables backups)"
  type        = number
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for RDS high availability"
  type        = bool
}

variable "env" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}

variable "secrets_name" {
  description = "AWS Secrets Manager secret name containing DB credentials. Ignored when self_service = true."
  type        = string
  default     = ""
}

variable "self_service" {
  description = "true for cicd_provider = \"none\" — generates backend/semantics DB credentials directly instead of requiring a pre-existing Secrets Manager secret."
  type        = bool
  default     = false
}
