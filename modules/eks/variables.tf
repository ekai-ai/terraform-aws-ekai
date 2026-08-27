variable "eks_cluster_role_arn" {
  description = "IAM role ARN for the EKS cluster"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster. null = latest AWS-supported version."
  type        = string
  default     = null
}

variable "public_access_cidrs" {
  description = "List of CIDR blocks allowed to access the EKS public API endpoint. Restrict to known IPs in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
