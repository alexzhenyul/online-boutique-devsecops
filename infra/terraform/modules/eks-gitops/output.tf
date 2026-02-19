# AWS EKS Managed GitOps Module - Outputs

output "gitops_configuration" {
  description = "Summary of GitOps configuration"
  value = {
    managed_argocd_iam_role = var.enable_managed_argocd
    helm_argocd             = var.enable_helm_argocd
    ack_enabled             = var.enable_ack
    kro_enabled             = var.enable_kro
    gitops_repo             = var.gitops_repo_url
    apps_path               = var.gitops_apps_path
  }
}

output "argocd_capability_role_arn" {
  description = "IAM Role ARN for EKS Managed Argo CD Capability (use with aws eks create-capability)"
  value       = var.enable_managed_argocd ? aws_iam_role.argocd_capability[0].arn : null
}

output "create_capability_command" {
  description = <<-EOT
    AWS CLI command to create the EKS Managed Argo CD capability.
    Run this command after the IAM role is created.

    PREREQUISITES:
    1. AWS Identity Center must be configured
    2. Update the user ID in the command
  EOT
  value       = var.enable_managed_argocd ? local.create_capability_command : null
  sensitive   = false
}

output "ack_role_arn" {
  description = "IAM Role ARN for ACK controllers"
  value       = var.enable_ack ? aws_iam_role.ack[0].arn : null
}

output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = var.enable_helm_argocd ? "argocd" : null
}

output "next_steps" {
  description = "Next steps after applying this module"
  value       = <<-EOT

    === GitOps Setup Complete ===

    ${var.enable_managed_argocd ? "AWS EKS Managed Argo CD:" : ""}
    ${var.enable_managed_argocd ? "1. Ensure AWS Identity Center (SSO) is configured" : ""}
    ${var.enable_managed_argocd ? "2. Run the create-capability command from the 'create_capability_command' output" : ""}
    ${var.enable_managed_argocd ? "3. Access ArgoCD via AWS EKS Console > Capabilities > Argo CD" : ""}

    ${var.enable_helm_argocd ? "Helm-based ArgoCD (Self-Managed):" : ""}
    ${var.enable_helm_argocd ? "1. Get initial admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d" : ""}
    ${var.enable_helm_argocd ? "2. Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443" : ""}
    ${var.enable_helm_argocd ? "3. Access ArgoCD UI at https://localhost:8080" : ""}

    Documentation:
    - AWS Managed ArgoCD: https://docs.aws.amazon.com/eks/latest/userguide/argocd.html
    - Self-Managed ArgoCD: https://argo-cd.readthedocs.io/
  EOT
}