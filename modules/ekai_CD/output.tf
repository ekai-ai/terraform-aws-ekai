output "argocd_app_name" {
  description = "ArgoCD application name — used as trigger for wait_for_alb null_resource"
  value       = argocd_application.ekai-saas.metadata[0].name
}
