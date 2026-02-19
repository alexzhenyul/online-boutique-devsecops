# Addons Layer - Workloads & GitOps
# Includes: ArgoCD, Controllers

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # Backend configured via backend.tf
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "online-boutique-devsecops"
      ManagedBy   = "terraform"
      Layer       = "addons"
    }
  }
}

# Kubernetes provider (Using Data from Foundation Layer)
provider "kubernetes" {
  host                   = data.terraform_remote_state.foundation.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.foundation.outputs.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.foundation.outputs.cluster_name]
  }
}

# Helm provider
provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.foundation.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.foundation.outputs.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.foundation.outputs.cluster_name]
    }
  }
}

locals {
  common_tags = {
    Environment = var.environment
    CostCenter  = "development"
    Layer       = "addons"
  }
}

# -----------------------------------------------------------------------------
# GitOps (ArgoCD)
# -----------------------------------------------------------------------------

module "eks_gitops" {
  source = "../../../modules/eks-gitops"

  cluster_name      = data.terraform_remote_state.foundation.outputs.cluster_name
  oidc_provider_arn = data.terraform_remote_state.foundation.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.foundation.outputs.oidc_provider_url

  # AWS Managed Argo CD (EKS Capability)
  enable_managed_argocd = var.enable_aws_managed_gitops

  # Helm-based ArgoCD (Self-Managed)
  enable_helm_argocd = var.enable_helm_argocd

  # AWS Controllers for Kubernetes
  enable_ack = var.enable_ack

  # Kube Resource Orchestrator
  enable_kro = var.enable_kro

  # AWS Load Balancer Controller
  enable_aws_load_balancer_controller = true

  # GitOps repository configuration
  deploy_root_application = var.enable_helm_argocd
  gitops_repo_url         = var.gitops_repo_url
  gitops_target_revision  = "main"
  gitops_apps_path        = "infra/argocd/apps"

  tags = local.common_tags
}