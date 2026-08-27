variable "eks_cluster_name" {
  description = "Name of the EKS cluster this node group belongs to"
  type        = string
}

variable "NODE_GROUP_ARN" {
  description = "IAM role ARN for the EKS node group"
  type        = string
}

variable "node_min_size" {
  description = "Minimum (and initial desired) number of nodes in the node group"
  type        = number
}

variable "mode_max_size" {
  description = "Maximum number of nodes in the node group"
  type        = number
}

variable "node_instance" {
  description = "EC2 instance type for worker nodes (e.g., c5.large)"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the node group"
  type        = list(string)
}

variable "ami_type" {
  description = "EKS node group AMI type. AL2023_x86_64_STANDARD required for K8s 1.33+ (AL2 is EOL for 1.33+)."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_disk_size" {
  description = "Worker node root disk size in GiB."
  type        = number
  default     = 80
}
