variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-southeast-4"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# State Configuration
variable "tf_state_bucket" {
  description = "Name of the S3 bucket for Terraform State (Required for Remote State lookup)"
  type        = string
}

# GitOps
variable "enable_aws_managed_gitops" {
  description = "Enable AWS Managed Argo CD"
  type        = bool
  default     = false
}

variable "enable_helm_argocd" {
  description = "Enable Helm-based Self-Managed Argo CD"
  type        = bool
  default     = true
}

variable "gitops_repo_url" {
  description = "URL of the GitOps repository"
  type        = string
  default     = "https://github.com/alexzhenyul/online-boutique-devsecops.git"
}

# Controllers
variable "enable_ack" {
  description = "Enable AWS Controllers for Kubernetes (ACK)"
  type        = bool
  default     = false
}

variable "enable_kro" {
  description = "Enable Kube Resource Orchestrator (KRO)"
  type        = bool
  default     = false
}