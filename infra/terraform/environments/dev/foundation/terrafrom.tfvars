# General
aws_region   = "ap-southeast-4"
environment  = "dev"
project_name = "devsecops"

# VPC
use_custom_vpc     = true
vpc_cidr           = "10.0.0.0/16"
az_count           = 2
single_nat_gateway = true
enable_flow_logs   = false

# EKS
kubernetes_version  = "1.35"
node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 3
capacity_type       = "ON_DEMAND"

# ECR
repository_name = "online-boutique-devsecops"

# GitHub OIDC
github_org  = "alexzhenyul"
github_repo = "online-boutique-devsecops"