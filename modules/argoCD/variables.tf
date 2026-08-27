variable "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is installed"
  type        = string
  default     = "argocd"
}

variable "argocd_admin_password_hashed" {
  description = "Bcrypt-hashed ArgoCD admin password passed to the Helm chart"
  type        = string
  sensitive   = true
}

variable "argocd_ingress_host" {
  description = "Hostname for the ArgoCD ingress endpoint (e.g., argocd.test.ekai.ai)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the ArgoCD DNS record"
  type        = string
}

variable "ssl_certificate_arn" {
  description = "ACM SSL certificate ARN for the ArgoCD ALB HTTPS listener"
  type        = string
}

variable "pub_subnet_ids" {
  description = "List of public subnet IDs for the ArgoCD ALB"
  type        = list(string)
}

variable "env" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}


