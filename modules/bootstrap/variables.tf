variable "region" {
  description = "AWS region (e.g. us-east-1). Must match the state bucket region."
  type        = string
}

variable "env" {
  description = "Environment slug (e.g. client1, dev, prod). Used in tags and state key."
  type        = string
}

variable "dns_zone" {
  description = "DNS zone for this env (e.g. client1.ekai.ai). Created here when manage_dns_zone = true."
  type        = string
}

variable "manage_dns_zone" {
  description = "If true, this layer creates the Route53 hosted zone. Set false when the zone already exists — pass route53_zone_id instead."
  type        = bool
  default     = true
}

variable "route53_zone_id" {
  description = "Pre-existing Route53 zone ID. Required when manage_dns_zone = false."
  type        = string
  default     = ""
}


variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "eks_cluster_name" {
  description = "Base EKS cluster name — used to tag subnets for ALB/ELB discovery"
  type        = string
}
