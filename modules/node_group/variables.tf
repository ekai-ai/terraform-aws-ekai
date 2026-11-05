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

  validation {
    condition = (
      can(regex("^[a-z]+[0-9]+g[a-z]*\\.", lower(var.node_instance)))
      == contains(["AL2023_ARM_64_STANDARD", "AL2_ARM_64", "BOTTLEROCKET_ARM_64", "BOTTLEROCKET_ARM_64_NVIDIA"], var.ami_type)
    )
    error_message = "node_instance's CPU architecture must match ami_type -- a Graviton (ARM) instance type (e.g. t4g.large, c7g.xlarge) needs an ARM ami_type (AL2023_ARM_64_STANDARD, AL2_ARM_64, BOTTLEROCKET_ARM_64, BOTTLEROCKET_ARM_64_NVIDIA); any other instance type needs an x86_64 ami_type."
  }
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
