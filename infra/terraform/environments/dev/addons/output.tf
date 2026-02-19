# Addons Outputs

output "gitops_type" {
  description = "GitOps approach being used"
  value = var.enable_helm_argocd ? (
    var.enable_aws_managed_gitops ? "Both: Helm ArgoCD + AWS Managed IAM Role" : "Helm-based ArgoCD (Self-Managed)"
    ) : (
    var.enable_aws_managed_gitops ? "AWS EKS Managed Argo CD (requires CLI setup)" : "None configured"
  )
}

output "gitops_next_steps" {
  description = "Next steps for GitOps setup"
  value       = module.eks_gitops.next_steps
}

output "create_argocd_capability_command" {
  description = "AWS CLI command to create EKS Managed Argo CD capability (if enabled)"
  value       = var.enable_aws_managed_gitops ? module.eks_gitops.create_capability_command : null
  sensitive   = false
}

# Passthrough useful foundation outputs for convenience
output "cluster_name" {
  value = data.terraform_remote_state.foundation.outputs.cluster_name
}