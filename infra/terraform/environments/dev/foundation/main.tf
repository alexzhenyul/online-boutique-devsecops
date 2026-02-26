# Foundation Layer - Base Infrastructure
# Includes: VPC, EKS Cluster, ECR, IAM Roles (OIDC)

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Backend configured via backend.tf
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "online-boutique-devsecops"
      ManagedBy   = "terraform"
      Layer       = "foundation"
    }
  }
}

locals {
  cluster_name = "${var.project_name}-${var.environment}"

  # VPC selection
  vpc_id     = var.use_custom_vpc ? module.vpc[0].vpc_id : data.aws_vpc.default[0].id
  subnet_ids = var.use_custom_vpc ? module.vpc[0].private_subnet_ids : data.aws_subnets.default[0].ids

  common_tags = {
    Environment = var.environment
    CostCenter  = "development"
    Layer       = "foundation"
  }
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

module "vpc" {
  source = "../../../modules/vpc"
  count  = var.use_custom_vpc ? 1 : 0

  cluster_name         = local.cluster_name
  vpc_cidr             = var.vpc_cidr
  az_count             = var.az_count
  single_nat_gateway   = var.single_nat_gateway
  enable_vpc_endpoints = var.enable_vpc_endpoints
  enable_flow_logs     = var.enable_flow_logs

  tags = local.common_tags
}

data "aws_vpc" "default" {
  count   = var.use_custom_vpc ? 0 : 1
  default = true
}

data "aws_subnets" "default" {
  count = var.use_custom_vpc ? 0 : 1
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------

module "eks" {
  source = "../../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = local.vpc_id
  subnet_ids = local.subnet_ids

  # Security settings
  endpoint_private_access   = true
  endpoint_public_access    = true
  public_access_cidrs       = ["0.0.0.0/0"]
  enable_secrets_encryption = true

  # Logging
  enabled_cluster_log_types = ["api", "audit"]
  log_retention_days        = 7

  # Node configuration
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = 30
  capacity_type       = var.capacity_type

  node_labels = {
    environment = var.environment
    workload    = "general"
  }

  tags = local.common_tags

  depends_on = [module.vpc]
}

# -----------------------------------------------------------------------------
# ECR Repository
# -----------------------------------------------------------------------------

module "ecr" {
  source = "../../../modules/ecr"

  repository_names = [
    "online-boutique/frontend",
    "online-boutique/cartservice",
    "online-boutique/checkoutservice",
    "online-boutique/currencyservice",
    "online-boutique/emailservice",
    "online-boutique/paymentservice",
    "online-boutique/productcatalogservice",
    "online-boutique/recommendationservice",
    "online-boutique/shippingservice",
    "online-boutique/adservice",
    "online-boutique/loadgenerator"
  ]

  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# GitHub OIDC
# -----------------------------------------------------------------------------

module "github_oidc" {
  source = "../../../modules/github-oidc"

  github_org  = var.github_org
  github_repo = var.github_repo
  tags        = local.common_tags
}