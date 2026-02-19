# AWS EKS Managed GitOps Module - Variables

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster (required for ACK)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the OIDC provider for the EKS cluster (required for ACK)"
  type        = string
}

# -----------------------------------------------------------------------------
# AWS EKS Managed Argo CD (EKS Capability)
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/argocd.html
#
# IMPORTANT: AWS Managed ArgoCD requires AWS Identity Center (SSO)
# Local users are NOT supported
# -----------------------------------------------------------------------------

variable "enable_managed_argocd" {
  description = <<-EOT
    Enable AWS EKS Managed Argo CD capability IAM role creation.
    NOTE: The actual capability must be created via AWS CLI, Console, or eksctl
    after the IAM role is created. Terraform does not have native support yet.

    PREREQUISITE: AWS Identity Center (SSO) must be configured.
  EOT
  type        = bool
  default     = false
}

variable "enable_secrets_manager_integration" {
  description = "Enable AWS Secrets Manager integration for ArgoCD capability"
  type        = bool
  default     = false
}

variable "enable_codeconnections_integration" {
  description = "Enable AWS CodeConnections integration for Git repository access"
  type        = bool
  default     = false
}

variable "codeconnections_arn" {
  description = "ARN of the CodeConnection for Git repository access (optional)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Helm-based ArgoCD (Self-Managed)
# Use this if you don't have AWS Identity Center or prefer self-managed
# -----------------------------------------------------------------------------

variable "enable_helm_argocd" {
  description = "Enable Helm-based ArgoCD installation (self-managed, doesn't require Identity Center)"
  type        = bool
  default     = true
}

variable "argocd_helm_version" {
  description = "Version of ArgoCD Helm chart"
  type        = string
  default     = "5.51.6"
}

variable "argocd_service_type" {
  description = "Service type for ArgoCD server (LoadBalancer, ClusterIP, NodePort)"
  type        = string
  default     = "ClusterIP"
}

variable "argocd_insecure" {
  description = "Disable TLS on ArgoCD server (for testing only)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# AWS Controllers for Kubernetes (ACK)
# Reference: https://aws-controllers-k8s.github.io/community/
# -----------------------------------------------------------------------------

variable "enable_ack" {
  description = "Enable AWS Controllers for Kubernetes"
  type        = bool
  default     = false
}

variable "ack_s3_version" {
  description = "Version of ACK S3 controller chart"
  type        = string
  default     = "1.0.12"
}

# -----------------------------------------------------------------------------
# Kube Resource Orchestrator (KRO)
# Reference: https://github.com/awslabs/kro
# -----------------------------------------------------------------------------

variable "enable_kro" {
  description = "Enable Kube Resource Orchestrator"
  type        = bool
  default     = false
}

variable "kro_version" {
  description = "Version of KRO Helm chart"
  type        = string
  default     = "0.1.0"
}

# -----------------------------------------------------------------------------
# AWS Load Balancer Controller
# -----------------------------------------------------------------------------

variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "aws_load_balancer_controller_version" {
  description = "Version of AWS Load Balancer Controller Helm chart"
  type        = string
  default     = "1.7.2"
}

# -----------------------------------------------------------------------------
# GitOps Repository Configuration
# -----------------------------------------------------------------------------

variable "deploy_root_application" {
  description = "Deploy the root ArgoCD Application resource (only for Helm-based ArgoCD)"
  type        = bool
  default     = true
}

variable "gitops_repo_url" {
  description = "URL of the GitOps repository"
  type        = string
  default     = "https://github.com/abhishekpanda0620/devsecops-platform-template.git"
}

variable "gitops_target_revision" {
  description = "Git revision to track (branch, tag, or commit SHA)"
  type        = string
  default     = "HEAD"
}

variable "gitops_apps_path" {
  description = "Path to ArgoCD applications in the repository"
  type        = string
  default     = "infra/argocd/apps"
}

# -----------------------------------------------------------------------------
# Common
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}