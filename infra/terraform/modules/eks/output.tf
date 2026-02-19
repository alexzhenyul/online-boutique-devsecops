# EKS Module Outputs

output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider for IRSA"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.main.id
}

output "node_group_arn" {
  description = "EKS node group ARN"
  value       = aws_eks_node_group.main.arn
}

output "node_group_role_arn" {
  description = "IAM role ARN for the node group"
  value       = aws_iam_role.node.arn
}

output "cluster_role_arn" {
  description = "IAM role ARN for the EKS cluster"
  value       = aws_iam_role.cluster.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for secrets encryption"
  value       = var.enable_secrets_encryption ? aws_kms_key.eks[0].arn : null
}

# Kubeconfig output for convenience
output "kubeconfig" {
  description = "kubectl config for the cluster"
  value = templatefile("${path.module}/templates/kubeconfig.tpl", {
    cluster_name                  = aws_eks_cluster.main.name
    cluster_endpoint              = aws_eks_cluster.main.endpoint
    cluster_certificate_authority = aws_eks_cluster.main.certificate_authority[0].data
    region                        = data.aws_region.current.id
  })
  sensitive = true
}