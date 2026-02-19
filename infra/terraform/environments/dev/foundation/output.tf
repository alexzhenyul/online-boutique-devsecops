# Foundation Outputs

# EKS (Critical for Addons Layer)
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA data"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "EKS OIDC Provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "EKS OIDC Provider URL"
  value       = module.eks.oidc_provider_url
}

# IAM
output "github_actions_role_arn" {
  description = "Role ARN to put in GitHub Secrets"
  value       = module.github_oidc.role_arn
}

# ECR
output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "ECR Repository Name"
  value       = module.ecr.repository_name
}

# VPC
output "vpc_id" {
  description = "VPC ID"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs"
  value       = local.subnet_ids
}