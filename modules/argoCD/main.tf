resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
  }
}

resource "helm_release" "argocd" {
  name            = "argocd"
  namespace       = kubernetes_namespace.argocd.metadata[0].name
  chart           = "argo-cd"
  repository      = "https://argoproj.github.io/argo-helm"
  timeout         = 1800
  cleanup_on_fail = true

  values = [
    yamlencode({
      server = {
        service = { type = "ClusterIP" }
        # Ingress managed separately as kubectl_manifest — destroy ordering below.
        ingress = { enabled = false }
      }
      configs = {
        params = { "server.insecure" = "true" }
        secret = { argocdServerAdminPassword = var.argocd_admin_password_hashed }
      }
    })
  ]
}

# Mirrors the Azure argocd module pattern exactly.
# force_conflicts = true takes ownership of ArgoCD's auto-created AppProject.
# Setting finalizers = [] ensures the finalizer is stripped on the APPLY pass
# so the controller-managed finalizer is gone when destroy runs.
resource "kubectl_manifest" "argocd_default_project" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name       = "default"
      namespace  = var.argocd_namespace
      finalizers = []
    }
    spec = {
      sourceRepos              = ["*"]
      destinations             = [{ namespace = "*", server = "https://kubernetes.default.svc" }]
      clusterResourceWhitelist = [{ group = "*", kind = "*" }]
    }
  })
  force_conflicts = true
  depends_on      = [helm_release.argocd]
}

# Destroy order (reversed from apply because of the depends_on chain):
#
#   1. kubectl_manifest.argocd_ingress  (~90 s — ALB controller deletes ALB)
#      ArgoCD controllers are still fully running during this entire wait.
#
#   2. kubectl_manifest.argocd_default_project  (< 1 s)
#      ArgoCD application-controller processes the AppProject finalizer instantly
#      (04-cicd already removed all Applications so the project is empty).
#      Helm starts within milliseconds — no reconciliation window for recreation.
#
#   3. helm_release.argocd  (fast — no stuck finalizers)
#
#   4. kubernetes_namespace.argocd  (empty → instant)
#
# Why this beats the null_resource/kubectl approach: ArgoCD processes its own
# finalizer cleanly when controllers are running. The previous approach of scaling
# controllers down introduced a sleep-based race condition.
resource "kubectl_manifest" "argocd_ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "argocd-server"
      namespace = var.argocd_namespace
      annotations = {
        "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"        = "ip"
        "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\":80},{\"HTTPS\":443}]"
        "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
        "alb.ingress.kubernetes.io/load-balancer-name" = "argocd-alb-${var.env}"
        "alb.ingress.kubernetes.io/subnets"            = join(",", var.pub_subnet_ids)
        "alb.ingress.kubernetes.io/certificate-arn"    = var.ssl_certificate_arn
        "alb.ingress.kubernetes.io/backend-protocol"   = "HTTP"
        "alb.ingress.kubernetes.io/healthcheck-path"   = "/healthz"
        "alb.ingress.kubernetes.io/healthcheck-port"   = "traffic-port"
        "alb.ingress.kubernetes.io/success-codes"      = "200"
      }
    }
    spec = {
      ingressClassName = "alb"
      rules = [{
        host = var.argocd_ingress_host
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend  = { service = { name = "argocd-server", port = { number = 80 } } }
          }]
        }
      }]
    }
  })

  depends_on = [helm_release.argocd, kubectl_manifest.argocd_default_project]
}

# ALB controller provisions the ALB after seeing the ingress — typically 90-120s.
resource "time_sleep" "wait_for_alb" {
  create_duration = "4m"
  depends_on      = [kubectl_manifest.argocd_ingress]
}

data "kubernetes_ingress_v1" "argocd_ingress" {
  metadata {
    name      = "argocd-server"
    namespace = var.argocd_namespace
  }
  depends_on = [time_sleep.wait_for_alb]
}

resource "aws_route53_record" "argocd" {
  zone_id = var.route53_zone_id
  name    = var.argocd_ingress_host
  type    = "CNAME"
  ttl     = 300
  records = [data.kubernetes_ingress_v1.argocd_ingress.status[0].load_balancer[0].ingress[0].hostname]
}
