# AWS EKS Managed GitOps Module
# Enables AWS EKS Capabilities including Managed Argo CD, ACK, and KRO
#
# IMPORTANT: Based on AWS Documentation (docs.aws.amazon.com/eks/latest/userguide/argocd.html)
# - EKS Managed Argo CD is an "EKS Capability", NOT an EKS Addon
# - It requires AWS Identity Center (SSO) for authentication - local users are NOT supported
# - Created via `aws eks create-capability` CLI command or AWS Console
# - Terraform does NOT have native support for EKS Capabilities yet
#
# This module provides:
# 1. IAM Capability Role required for EKS Managed Argo CD
# 2. A null_resource to create the capability via AWS CLI (when available)
# 3. Helm-based ArgoCD installation as a fallback option
# 4. ACK and KRO installation via Helm
# ACK (AWS Controllers for Kubernetes)— manage AWS resources (S3, RDS, etc.) using kubectl and Kubernetes YAML instead of Terraform/console
# KRO (Kube Resource Orchestrator)— bundle multiple Kubernetes resources into a single reusable custom resource with a simple API

terraform {
  required_version = ">= 1.5.0"

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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# -----------------------------------------------------------------------------
# AWS EKS Managed Argo CD (EKS Capability)
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/argocd.html
#
# PREREQUISITES (must be configured BEFORE using AWS Managed ArgoCD):
# 1. AWS Identity Center (SSO) must be configured
# 2. Users/Groups must be created in Identity Center
# -----------------------------------------------------------------------------

# IAM Capability Role for EKS Managed Argo CD
# Trust policy allows capabilities.eks.amazonaws.com to assume the role
resource "aws_iam_role" "argocd_capability" {
  count = var.enable_managed_argocd ? 1 : 0

  name = "${var.cluster_name}-argocd-capability-role"

  # Trust policy per AWS documentation
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "capabilities.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-argocd-capability-role"
  })
}

# Optional: Policy for Secrets Manager integration
resource "aws_iam_role_policy" "argocd_secrets" {
  count = var.enable_managed_argocd && var.enable_secrets_manager_integration ? 1 : 0

  name = "${var.cluster_name}-argocd-secrets-policy"
  role = aws_iam_role.argocd_capability[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:secret:argocd/*"
      }
    ]
  })
}

# Optional: Policy for CodeConnections (Git repository access)
resource "aws_iam_role_policy" "argocd_codeconnections" {
  count = var.enable_managed_argocd && var.enable_codeconnections_integration ? 1 : 0

  name = "${var.cluster_name}-argocd-codeconnections-policy"
  role = aws_iam_role.argocd_capability[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codeconnections:UseConnection",
          "codeconnections:GetConnection"
        ]
        Resource = var.codeconnections_arn != "" ? var.codeconnections_arn : "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# EKS Capability Creation
# NOTE: As of Dec 2024, Terraform AWS provider does not have native support
# for EKS Capabilities. Use AWS CLI, Console, or eksctl to create.
#
# The IAM role above is created by Terraform, then you run:
# aws eks create-capability \
#   --cluster-name <cluster> \
#   --capability-name <name> \
#   --type ARGOCD \
#   --role-arn <role-arn-from-terraform-output> \
#   --configuration '<json-config>'
# -----------------------------------------------------------------------------

# Output the CLI command to create the capability
locals {
  argocd_capability_role_arn = var.enable_managed_argocd ? aws_iam_role.argocd_capability[0].arn : ""

  create_capability_command_template = <<-EOT
# Prerequisites:
# 1. AWS Identity Center must be configured
# 2. Get your Identity Center Instance ARN and User/Group IDs

# Set environment variables
export IDC_INSTANCE_ARN=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)
export IDC_USER_ID=$(aws identitystore list-users \
  --identity-store-id $(aws sso-admin list-instances --query 'Instances[0].IdentityStoreId' --output text) \
  --query 'Users[?UserName==`your-username`].UserId' --output text)

# Create the Argo CD capability
aws eks create-capability \
  --region ${data.aws_region.current.id} \
  --cluster-name ${var.cluster_name} \
  --capability-name ${var.cluster_name}-argocd \
  --type ARGOCD \
  --role-arn ROLE_ARN_PLACEHOLDER \
  --delete-propagation-policy RETAIN \
  --configuration '{
    "argoCd": {
      "awsIdc": {
        "idcInstanceArn": "'$IDC_INSTANCE_ARN'",
        "idcRegion": "${data.aws_region.current.id}"
      },
      "rbacRoleMappings": [{
        "role": "ADMIN",
        "identities": [{
          "id": "'$IDC_USER_ID'",
          "type": "SSO_USER"
        }]
      }]
    }
  }'
EOT

  create_capability_command = var.enable_managed_argocd ? replace(
    local.create_capability_command_template,
    "ROLE_ARN_PLACEHOLDER",
    aws_iam_role.argocd_capability[0].arn
  ) : ""
}

# -----------------------------------------------------------------------------
# Alternative: Helm-based ArgoCD (Self-Managed on EKS)
# Use this if you don't have AWS Identity Center or prefer self-managed
# -----------------------------------------------------------------------------

resource "helm_release" "argocd" {
  count = var.enable_helm_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_helm_version
  namespace        = "argocd"
  create_namespace = true

  values = [
    yamlencode({
      server = {
        service = {
          type = var.argocd_service_type
        }
      }
      configs = {
        params = {
          "server.insecure" = var.argocd_insecure
        }
      }
    })
  ]

  depends_on = [data.aws_eks_cluster.cluster]
}

# Deploy root ArgoCD Application (for Helm-based ArgoCD)
# Using null_resource with kubectl instead of kubernetes_manifest to avoid
# CRD validation errors during `terraform plan` (the CRDs don't exist until
# the ArgoCD Helm chart is applied)
resource "null_resource" "argocd_root_app" {
  count = var.enable_helm_argocd && var.deploy_root_application ? 1 : 0

  triggers = {
    gitops_repo_url        = var.gitops_repo_url
    gitops_target_revision = var.gitops_target_revision
    gitops_apps_path       = var.gitops_apps_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Configure kubectl to use the EKS cluster
      echo "Configuring kubectl for EKS cluster ${var.cluster_name}..."
      aws eks update-kubeconfig --name ${var.cluster_name} --region ${data.aws_region.current.id}

      # Wait for ArgoCD CRDs to be available (max 5 minutes)
      echo "Waiting for ArgoCD CRDs to be installed..."
      for i in $(seq 1 30); do
        if kubectl get crd applications.argoproj.io &>/dev/null; then
          echo "ArgoCD CRDs are available!"
          break
        fi
        if [ $i -eq 30 ]; then
          echo "ERROR: Timed out waiting for ArgoCD CRDs"
          exit 1
        fi
        echo "Waiting for ArgoCD CRDs... attempt $i/30"
        sleep 10
      done

      # Wait for ArgoCD server to be ready
      echo "Waiting for ArgoCD server to be ready..."
      kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || true

      # Apply the root Application
      cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: devsecops-platform
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: ${var.gitops_target_revision}
    path: ${var.gitops_apps_path}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
    EOT
  }

  depends_on = [helm_release.argocd]
}

# -----------------------------------------------------------------------------
# AWS Controllers for Kubernetes (ACK)
# Reference: https://aws-controllers-k8s.github.io/community/
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ack" {
  count = var.enable_ack ? 1 : 0

  name = "${var.cluster_name}-ack-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringLike = {
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:ack-system:ack-*"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ack-controller-role"
  })
}

# ACK S3 Controller
resource "helm_release" "ack_s3" {
  count = var.enable_ack ? 1 : 0

  name             = "ack-s3-controller"
  repository       = "oci://public.ecr.aws/aws-controllers-k8s"
  chart            = "s3-chart"
  version          = var.ack_s3_version
  namespace        = "ack-system"
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.ack[0].arn
  }

  set {
    name  = "aws.region"
    value = data.aws_region.current.id
  }

  depends_on = [aws_iam_role.ack]
}

# -----------------------------------------------------------------------------
# Kube Resource Orchestrator (KRO)
# Reference: https://github.com/awslabs/kro
# -----------------------------------------------------------------------------

resource "helm_release" "kro" {
  count = var.enable_kro ? 1 : 0

  name             = "kro"
  repository       = "https://awslabs.github.io/kro"
  chart            = "kro"
  version          = var.kro_version
  namespace        = "kro-system"
  create_namespace = true

  depends_on = [data.aws_eks_cluster.cluster]
}

# -----------------------------------------------------------------------------
# AWS Load Balancer Controller
# -----------------------------------------------------------------------------

resource "aws_iam_role" "aws_load_balancer_controller" {
  count = var.enable_aws_load_balancer_controller ? 1 : 0

  name = "${var.cluster_name}-aws-load-balancer-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-aws-load-balancer-controller"
  })
}

resource "aws_iam_role_policy" "aws_load_balancer_controller" {
  count = var.enable_aws_load_balancer_controller ? 1 : 0

  name = "${var.cluster_name}-aws-load-balancer-controller-policy"
  role = aws_iam_role.aws_load_balancer_controller[0].id

  # This policy allows the controller to manage ALBs/NLBs
  # In a real setup, you should download the official policy.json from AWS
  # For simplicity, we are using a broad policy here, but in prod use restricted permissions
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteSecurityGroup",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "helm_release" "aws_load_balancer_controller" {
  count = var.enable_aws_load_balancer_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_version
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.aws_load_balancer_controller[0].arn
  }

  set {
    name  = "region"
    value = data.aws_region.current.id
  }

  set {
    name  = "vpcId"
    value = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
  }

  depends_on = [
    aws_iam_role.aws_load_balancer_controller,
    aws_iam_role_policy.aws_load_balancer_controller
  ]
}