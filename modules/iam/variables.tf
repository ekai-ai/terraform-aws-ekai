variable "env" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}

variable "region" {
  description = "AWS region — used as a suffix in IAM role names to ensure uniqueness"
  type        = string
}
