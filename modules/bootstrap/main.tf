# ──────────────────────────────────────────────────────────────────────────────
# Layer 01 — Bootstrap (Route53 zone + ACM certificate)
# ──────────────────────────────────────────────────────────────────────────────
# What this layer provisions:
#   • Route53 hosted zone for this env (when manage_dns_zone = true)
#   • ACM wildcard certificate (*.dns_zone + dns_zone) with DNS validation
#   • Route53 DNS validation records + waits for validation
#
# What it reads (client-owned, must exist before apply when manage_dns_zone = false):
#   • Existing Route53 zone — pass route53_zone_id in tfvars
#
# What it does NOT provision (out-of-band — see scripts/init-state-backend.sh):
#   • S3 state bucket + versioning + encryption
#
# Outputs (consumed by Layers 02/03/04 via tfvars or terraform_remote_state):
#   • route53_zone_id, route53_zone_name, route53_name_servers
#   • ssl_certificate_arn
# ──────────────────────────────────────────────────────────────────────────────

# ── Route53 zone ──────────────────────────────────────────────────────────────
resource "aws_route53_zone" "main" {
  count = var.manage_dns_zone ? 1 : 0
  name  = var.dns_zone

  tags = {
    Name      = var.dns_zone
    Env       = var.env
    ManagedBy = "terraform"
    Layer     = "01-bootstrap"
  }
}

# Reference an existing zone when manage_dns_zone = false
data "aws_route53_zone" "existing" {
  count   = var.manage_dns_zone ? 0 : 1
  zone_id = var.route53_zone_id
}

locals {
  zone_id      = var.manage_dns_zone ? aws_route53_zone.main[0].zone_id : var.route53_zone_id
  zone_name    = var.manage_dns_zone ? aws_route53_zone.main[0].name : data.aws_route53_zone.existing[0].name
  name_servers = var.manage_dns_zone ? aws_route53_zone.main[0].name_servers : []
}

# ── ACM certificate (wildcard + apex) ─────────────────────────────────────────
# Always created by Terraform — never provided externally.
# Uses DNS validation via the Route53 zone above (new or existing).
resource "aws_acm_certificate" "main" {
  domain_name               = var.dns_zone
  subject_alternative_names = ["*.${var.dns_zone}"]
  validation_method         = "DNS"

  tags = {
    Name      = var.dns_zone
    Env       = var.env
    ManagedBy = "terraform"
    Layer     = "01-bootstrap"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── DNS validation records ────────────────────────────────────────────────────
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = local.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  allow_overwrite = true
}

# ── Wait for certificate validation ──────────────────────────────────────────
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ── VPC ───────────────────────────────────────────────────────────────────────
# Lives here (not in 02-cluster) because VPC is permanent infrastructure —
# same lifecycle as Route53 and ACM.
# Benefit on destroy: 02-cluster removes EKS/RDS only. By the time
# 01-bootstrap destroy runs, EKS control-plane ENIs are long gone →
# subnets and IGW delete cleanly without DependencyViolation.
module "vpc" {
  source               = "../vpc"
  region               = var.region
  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  eks_cluster_name     = var.eks_cluster_name
}
