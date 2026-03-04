# Infrastructure — Terraform on AWS

This document covers all AWS infrastructure provisioned via Terraform for the Online Boutique DevSecOps project.

---

## Table of Contents

- [Infrastructure — Terraform on AWS](#infrastructure--terraform-on-aws)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Repository Structure](#repository-structure)
  - [Prerequisites](#prerequisites)
  - [Remote State Setup](#remote-state-setup)
  - [Modules](#modules)
    - [Networking (VPC)](#networking-vpc)
    - [EKS Cluster](#eks-cluster)
    - [Jenkins EC2](#jenkins-ec2)
    - [Monitoring](#monitoring)
  - [Deployment Order](#deployment-order)
  - [Tear Down](#tear-down)
  - [Security Design](#security-design)

---

## Overview

All AWS infrastructure is managed as code using Terraform. No manual console changes are made — every resource is tracked, versioned, and reproducible.

| Setting | Value |
|---|---|
| Cloud Provider | AWS |
| Region | `ap-southeast-4` (Melbourne) |
| Terraform version | ≥ 1.5 |
| State backend | S3 + DynamoDB |
| EKS version | 1.29+ |

---

## Repository Structure

```
infra/
├── eks/               # EKS cluster and node groups
├── networking/        # VPC, subnets, route tables, security groups
├── jenkins/           # Jenkins EC2 instance
└── monitoring/        # Prometheus + Grafana Helm deployment
```

---

## Prerequisites

```bash
# AWS CLI
aws configure
# Set region to ap-southeast-4

# Terraform
terraform -version   # must be >= 1.5

# kubectl
kubectl version --client

# Helm
helm version
```

Ensure the AWS IAM user/role running Terraform has permissions for: EC2, EKS, VPC, IAM, S3, DynamoDB, ECR.

---

## Remote State Setup

Before provisioning any module, create the S3 bucket and DynamoDB table for Terraform state:

```bash
# Create S3 bucket for state
aws s3api create-bucket \
  --bucket online-boutique-tfstate \
  --region ap-southeast-4 \
  --create-bucket-configuration LocationConstraint=ap-southeast-4

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket online-boutique-tfstate \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket online-boutique-tfstate \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms"}}]
  }'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name online-boutique-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-4
```

Each module's `backend.tf` references this bucket:

```hcl
terraform {
  backend "s3" {
    bucket         = "online-boutique-tfstate"
    key            = "eks/terraform.tfstate"
    region         = "ap-southeast-4"
    dynamodb_table = "online-boutique-tflock"
    encrypt        = true
  }
}
```

---

## Modules

### Networking (VPC)

**Path:** `infra/networking/`

Creates the foundational network layer used by all other modules.

**Resources provisioned:**
- VPC with DNS hostnames enabled
- 2× Public subnets (across AZs) — for load balancers
- 2× Private subnets (across AZs) — for EKS nodes and Jenkins
- Internet Gateway
- NAT Gateway (in public subnet — allows private resources to reach internet)
- Route tables for public and private subnets
- VPC Flow Logs to S3 for network audit

```bash
cd infra/networking
terraform init
terraform plan
terraform apply
```

**Key outputs used by other modules:**
- `vpc_id`
- `private_subnet_ids`
- `public_subnet_ids`

---

### EKS Cluster

**Path:** `infra/eks/`

Provisions the Kubernetes cluster that runs Online Boutique, ArgoCD, and the monitoring stack.

**Resources provisioned:**
- EKS Control Plane (managed by AWS)
- Managed Node Group (private subnets, `t3.medium` nodes)
- IAM roles for the cluster and node group
- IRSA (IAM Roles for Service Accounts) — allows pods to assume IAM roles without static keys
- EKS Addons: `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`
- ECR repositories per microservice
- `aws-auth` ConfigMap update for Jenkins/admin access

```bash
cd infra/eks
terraform init
terraform plan
terraform apply
```

**After apply — configure kubectl:**
```bash
aws eks update-kubeconfig \
  --region ap-southeast-4 \
  --name online-boutique-eks
```

**Node Group Configuration:**

| Setting | Value |
|---|---|
| Instance type | `t3.medium` |
| Min nodes | 2 |
| Max nodes | 4 |
| Desired nodes | 2 |
| Subnet | Private (no public IP) |
| AMI type | `AL2_x86_64` |

---

### Jenkins EC2

**Path:** `infra/jenkins/`

Provisions the Jenkins server used for CI.

**Resources provisioned:**
- EC2 instance (`t3.medium`, Ubuntu 22.04 LTS)
- IAM instance profile with scoped permissions (ECR push, SSM access)
- Security group: port 8080 (Jenkins UI) open to your IP only; port 22 restricted
- Elastic IP for stable DNS
- EBS volume for Jenkins home directory (`/var/lib/jenkins`)

```bash
cd infra/jenkins
terraform init
terraform plan
terraform apply
```

**After provisioning**, SSH in and install required tools — see [`jenkins/README.md`](./jenkins/README.md) for the full tool installation guide.

**IAM permissions granted to Jenkins instance:**
- `ecr:GetAuthorizationToken`
- `ecr:BatchCheckLayerAvailability`
- `ecr:PutImage`
- `ecr:InitiateLayerUpload`
- `ecr:UploadLayerPart`
- `ecr:CompleteLayerUpload`
- `ssm:GetParameter` (for secrets if needed)

---

### Monitoring

**Path:** `infra/monitoring/`

Deploys Prometheus and Grafana into the EKS cluster using the `kube-prometheus-stack` Helm chart.

```bash
cd infra/monitoring
terraform init
terraform apply
# or via Helm directly:
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f values.yaml
```

See [`monitoring/README.md`](./monitoring/README.md) for dashboard setup and Grafana access.

---

## Deployment Order

Modules have dependencies — provision in this order:

```
1. Remote State (S3 + DynamoDB)  ← manual, one-time
2. infra/networking/             ← VPC must exist first
3. infra/eks/                    ← depends on VPC outputs
4. infra/jenkins/                ← depends on VPC outputs
5. infra/monitoring/             ← deploys into EKS (must exist)
```

---

## Tear Down

To destroy all resources (in reverse order):

```bash
cd infra/monitoring && terraform destroy
cd infra/jenkins   && terraform destroy
cd infra/eks       && terraform destroy
cd infra/networking && terraform destroy
```

>  Destroying the EKS cluster will delete all running workloads. Ensure no critical data is in-cluster before destroying.

---

## Security Design

| Layer | Control |
|---|---|
| Network | Worker nodes in private subnets — no public IP |
| Network | NAT Gateway for egress; no direct inbound to nodes |
| IAM | IRSA — pods get minimum required AWS permissions via service account annotation |
| IAM | Jenkins EC2 uses instance profile — no static keys on the server |
| IAM | Least-privilege policies per resource type |
| State | S3 remote state encrypted with SSE-KMS |
| State | DynamoDB state locking prevents concurrent applies |
| Secrets | No hardcoded credentials in Terraform code; secrets via AWS SSM / Jenkins credentials |
| EKS | API server endpoint access restricted to known CIDRs |
| EKS | Envelope encryption enabled for Kubernetes secrets at rest |
