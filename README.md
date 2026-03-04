# Online Boutique — Production DevSecOps Pipeline

> A production-grade DevSecOps implementation built on top of Google's [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) microservices demo — demonstrating a complete, secure software delivery lifecycle with automated CI security gates, GitOps-driven deployment, Infrastructure as Code, and full-stack observability.

---

## 📌 Table of Contents

- [Online Boutique — Production DevSecOps Pipeline](#online-boutique--production-devsecops-pipeline)
  - [📌 Table of Contents](#-table-of-contents)
  - [Project Overview](#project-overview)
  - [🏗️ Architecture](#️-architecture)
  - [Tech Stack](#tech-stack)
  - [Repository Structure](#repository-structure)
  - [CI Pipeline — Jenkins](#ci-pipeline--jenkins)
    - [Smart Change Detection](#smart-change-detection)
    - [Automated Versioning](#automated-versioning)
    - [Security Stages](#security-stages)
    - [Build \& Publish](#build--publish)
    - [GitOps Update](#gitops-update)
    - [Email Notifications](#email-notifications)
  - [CD — ArgoCD GitOps](#cd--argocd-gitops)
  - [Infrastructure — Terraform](#infrastructure--terraform)
  - [Monitoring \& Observability](#monitoring--observability)
  - [Security Implementation](#security-implementation)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [1. Provision Infrastructure](#1-provision-infrastructure)
    - [2. Configure kubectl](#2-configure-kubectl)
    - [3. Install ArgoCD](#3-install-argocd)
    - [4. Bootstrap Applications](#4-bootstrap-applications)
    - [5. Configure Jenkins Credentials](#5-configure-jenkins-credentials)
  - [Roadmap](#roadmap)
  - [Section READMEs](#section-readmes)

---

## Project Overview

This project demonstrates a **production-ready DevSecOps pipeline** for a cloud-native microservices application. Security is embedded at every stage of the SDLC — from the first `git push` through to runtime — using industry-standard open-source tooling on AWS.

The application workload is **Google's Online Boutique**, an 11-microservice e-commerce platform written across Go, Python, C#, and Node.js — a realistic, polyglot target that exercises every part of the pipeline.

**Core principles:**
- **Shift security left** — vulnerabilities are caught before any artifact reaches a registry
- **GitOps as the single source of truth** — all deployments are declarative, auditable, and automated
- **Everything as code** — infrastructure, pipeline, manifests, and policies are all version-controlled
- **Full observability** — metrics, dashboards, and alerts for both the application and the pipeline itself

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Developer Workstation                      │
│               git push → Jenkins webhook triggered              │
└───────────────────────────┬─────────────────────────────────────┘
                            │
            ┌───────────────▼───────────────┐
            │         Jenkins CI            │
            │  ┌────────────────────────┐   │
            │  │  1. Detect Changed     │   │
            │  │     Microservice       │   │
            │  │  2. Gitleaks           │◄──┼── Blocks on secrets
            │  │  3. SonarQube SAST     │◄──┼── Blocks on quality gate
            │  │  4. OWASP Dep. Check   │◄──┼── Blocks on CVSS ≥ 8.0
            │  │  5. Trivy FS Scan      │◄──┼── Blocks on HIGH/CRITICAL
            │  │  6. Hadolint           │   │
            │  │  7. Docker Build       │   │
            │  │  8. Trivy Image Scan   │◄──┼── Blocks on HIGH/CRITICAL
            │  │  9. Push to DockerHub  │   │
            │  │  10. Update Kustomize  │   │
            │  │  11. Tag Git Commit    │   │
            │  └────────────────────────┘   │
            └───────────────┬───────────────┘
                            │  commits new image tag to gitops/
            ┌───────────────▼───────────────┐
            │          ArgoCD               │
            │  Watches gitops/ overlays     │
            │  Syncs dev / staging / prod   │
            └───────────────┬───────────────┘
                            │
        ┌───────────────────▼────────────────────┐
        │         AWS EKS Cluster                │
        │    (ap-southeast-4, Melbourne)         │
        │                                        │
        │  ┌──────────────────────────────────┐  │
        │  │   Online Boutique (11 services)  │  │
        │  │   dev | staging | prod overlays  │  │
        │  └──────────────────────────────────┘  │
        │  ┌────────────────┐ ┌───────────────┐  │
        │  │   Prometheus   │ │    Grafana    │  │
        │  └────────────────┘ └───────────────┘  │
        └────────────────────────────────────────┘
```

---

## Tech Stack

| Category | Tool | Role |
|---|---|---|
| **Application** | Google Online Boutique | 11-service polyglot microservices workload |
| **CI** | Jenkins | Pipeline orchestration and security gate enforcement |
| **CD / GitOps** | ArgoCD | Declarative, automated Kubernetes deployments |
| **Infrastructure** | Terraform | AWS resource provisioning (IaC) |
| **Container Orchestration** | Kubernetes (EKS) | Workload runtime — ap-southeast-4 |
| **Container Registry** | Docker Hub / AWS ECR | Image storage and distribution |
| **Secret Scanning** | Gitleaks | Detects credentials and secrets in source code |
| **SAST** | SonarQube | Static code analysis + quality gate enforcement |
| **SCA** | OWASP Dependency-Check | CVE scanning for third-party dependencies (blocks CVSS ≥ 8.0) |
| **Filesystem Scan** | Trivy FS | Scans source + dependencies before Docker build |
| **Dockerfile Lint** | Hadolint | Enforces Dockerfile best practices |
| **Image Scan** | Trivy Image | Scans the final built image for HIGH/CRITICAL CVEs |
| **Versioning** | Conventional Commits + Semver | Automated semantic version bumping per microservice |
| **GitOps Manifests** | Kustomize | Per-environment overlay management (dev/staging/prod) |
| **Monitoring** | Prometheus + Grafana | Metrics collection and dashboards |
| **Notifications** | Jenkins Email Ext | HTML pipeline summary emails with scan results |

---

## Repository Structure

```
online-boutique-devsecops/
│
├── app/
│   └── microservices-demo/            # Google Online Boutique source
│       └── src/
│           ├── adservice/             # Java
│           ├── cartservice/           # C#
│           ├── checkoutservice/       # Go
│           ├── currencyservice/       # Node.js
│           ├── emailservice/          # Python
│           ├── frontend/              # Go
│           ├── loadgenerator/         # Python / Locust
│           ├── paymentservice/        # Node.js
│           ├── productcatalogservice/ # Go
│           ├── recommendationservice/ # Python
│           └── shippingservice/       # Go
│
├── gitops/
│   └── k8s/
│       ├── base/                      # Base Kubernetes manifests
│       └── overlays/
│           ├── dev/                   # Dev: pinned to git SHA (every build)
│           ├── staging/               # Staging: pinned to semver
│           └── prod/                  # Prod: pinned to exact semver
│
├── infra/                             # Terraform infrastructure
│   ├── eks/                           # EKS cluster + node groups
│   ├── networking/                    # VPC, subnets, security groups
│   ├── jenkins/                       # Jenkins EC2 server
│   └── monitoring/                    # Prometheus / Grafana stack
│
├── Jenkinsfile                        # Declarative CI pipeline
└── .gitignore
```

---

## CI Pipeline — Jenkins

The pipeline is defined in the root `Jenkinsfile` and runs on every push to `main`. It detects **which microservice changed**, runs all security checks scoped to that service, and produces a versioned, fully-scanned image — automatically.

### Smart Change Detection

The first stage diffs `HEAD~1..HEAD` to identify which microservice directory changed under `app/microservices-demo/src/`. It then auto-detects the **language** of that service (Java Maven/Gradle, Go, Node.js, Python, C#) to configure downstream stages correctly. If no microservice source changed, the pipeline exits cleanly as `NOT_BUILT`.

A `[skip ci]` guard prevents infinite loops from CI-generated commits (e.g. the Kustomize manifest update stage).

### Automated Versioning

Versioning follows **Conventional Commits** — the pipeline reads the commit message to determine the bump type automatically:

| Commit Prefix | Bump | Example |
|---|---|---|
| `feat:` | **minor** | `1.2.0 → 1.3.0` |
| `BREAKING CHANGE:` or `type!:` | **major** | `1.2.0 → 2.0.0` |
| `fix:`, `chore:`, anything else | **patch** | `1.2.0 → 1.2.1` |

Each microservice has its own independent version history tracked via Git tags in the format `<service>/<semver>` (e.g. `frontend/1.4.2`). Each image is pushed with three tags: `semver`, `git-sha`, and `latest`.

### Security Stages

Every stage below is a **hard gate** — a failure stops the pipeline immediately and prevents the artifact from advancing.

| Stage | Tool | Block Condition |
|---|---|---|
| **Secret Scanning** | Gitleaks | Any secret or credential detected in service source |
| **SAST** | SonarQube | Language-aware static analysis; quality gate must pass |
| **SCA** | OWASP Dependency-Check | Any dependency CVE with CVSS ≥ 8.0 |
| **Filesystem Scan** | Trivy FS | Any HIGH or CRITICAL CVE in source/deps before build |
| **Dockerfile Lint** | Hadolint | Best-practice violations logged (configurable to block) |
| **Image Scan** | Trivy Image | Any HIGH or CRITICAL unfixed CVE in the final image |

All scan reports are archived as build artifacts on every run — pass or fail — for audit and compliance:

```
gitleaks-report.json
dependency-check-report.html
dependency-check-report.json
trivy-fs-report.json
hadolint-report.json
trivy-image-report.json
```

### Build & Publish

Docker images are built with **BuildKit** and OCI-standard labels (`version`, `revision`, `created`, `service`) for full traceability. Images are pushed to **Docker Hub** (`alexzhenyul/online-boutique-dev`) with AWS ECR (`253343486660.dkr.ecr.ap-southeast-4.amazonaws.com/online-boutique/<service>`) configured as the production target.

### GitOps Update

After a successful image push, the pipeline runs `kustomize edit set image` to update the relevant overlay(s) and commits back to `main` with `[skip ci]`:

| Environment | Image Tag Strategy | Purpose |
|---|---|---|
| `dev` | `git-sha` (e.g. `a1b2c3d4`) | Triggers ArgoCD on every single build |
| `staging` | `semver` (e.g. `1.4.2`) | Stable named release for QA |
| `prod` | `semver` (e.g. `1.4.2`) | Exact, auditable production version |

A Git tag `<service>/<semver>` is pushed to the repository to anchor each release in history.

### Email Notifications

On every pipeline completion (success or failure), an **HTML summary email** is sent with:
- Build metadata — service, version, git SHA, branch, duration, build URL
- Per-stage status table with contextual notes
- Direct links to every archived scan report
- Color-coded header: green (success) / amber (unstable) / red (failure)

---

## CD — ArgoCD GitOps

The CI pipeline **never deploys directly to Kubernetes**. It only commits updated image tags to `gitops/` and lets ArgoCD take over:

```
Jenkins commits new image tag → gitops/k8s/overlays/<env>/kustomization.yaml
         ↓
ArgoCD detects drift between desired Git state and live cluster state
         ↓
ArgoCD applies updated Kustomize overlay to EKS
         ↓
Kubernetes performs rolling update → health checks pass
         ↓
Deployment recorded in ArgoCD sync history (Git commit = audit log)
```

Every production deployment is backed by a Git commit — fully auditable, instantly reversible with a `git revert`, and not dependent on Jenkins being available.

> See [`gitops/README.md`](./gitops/README.md) for ArgoCD application setup and environment promotion.

---

## Infrastructure — Terraform

All AWS infrastructure is defined in `infra/` — no manual console changes. Every resource is tracked, versioned, and fully reproducible.

**Resources provisioned:**
- **VPC** — public/private subnets across multiple AZs in ap-southeast-4
- **EKS Cluster** — managed node groups with IRSA (IAM Roles for Service Accounts)
- **EC2** — Jenkins server with scoped IAM instance profile
- **AWS ECR** — private container registries per microservice
- **S3 + DynamoDB** — Terraform remote state with locking and SSE-KMS encryption
- **Security Groups** — least-privilege ingress/egress per component

> See [`infra/README.md`](./infra/README.md) for full Terraform module breakdown and usage.

---

## Monitoring & Observability

The monitoring stack is deployed into EKS using the **kube-prometheus-stack** Helm chart.

**Prometheus** scrapes metrics from:
- All 11 Online Boutique microservices
- Kubernetes node and control-plane exporters
- Jenkins (Prometheus metrics plugin)
- ArgoCD (built-in `/metrics` endpoint)

**Grafana** dashboards cover:
- Application golden signals — latency, traffic, error rate, saturation
- Kubernetes cluster health — CPU, memory, pod restarts, node pressure
- CI pipeline trends — build duration and failure rate per microservice
- Security scan trends — CVE counts over time per service

> See [`infra/monitoring/README.md`](./infra/monitoring/README.md) for setup and dashboard import.

---

## Security Implementation

Security is layered across every part of the stack:

**Source Code**
- Gitleaks blocks any credential or secret from entering the codebase

**CI Pipeline**
- SonarQube performs language-aware SAST with an enforced quality gate
- OWASP Dependency-Check audits all third-party libraries against the NVD database (CVSS ≥ 8.0 blocks the build)
- Trivy FS catches vulnerabilities in source and dependencies before the image is built
- Hadolint enforces Dockerfile best practices (no `latest` base tags, no `apt-get upgrade`, etc.)
- Trivy Image validates the final built image against HIGH/CRITICAL unfixed CVEs

**Container & Kubernetes**
- OCI labels on every image for traceability — version, git SHA, build timestamp, service name
- Resource requests and limits enforced on all pods
- Network Policies restrict pod-to-pod communication to declared routes only
- Kustomize overlays enforce environment-specific security configuration

**Infrastructure**
- IRSA ensures pods only receive the minimum AWS permissions they need
- Worker nodes deployed in private subnets — no direct public IP assignment
- Terraform remote state encrypted at rest (S3 SSE-KMS) with DynamoDB state locking

---

## Getting Started

### Prerequisites

- AWS CLI configured for `ap-southeast-4`
- Terraform ≥ 1.5
- kubectl + kustomize
- Helm ≥ 3.x
- ArgoCD CLI
- Jenkins instance (EC2 provisioned via `infra/jenkins/`)

### 1. Provision Infrastructure

```bash
cd infra/eks
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 2. Configure kubectl

```bash
aws eks update-kubeconfig \
  --region ap-southeast-4 \
  --name <cluster-name>
```

### 3. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 4. Bootstrap Applications

```bash
kubectl apply -f gitops/applications/
```

ArgoCD will sync and deploy the Online Boutique and monitoring stack across all three environments automatically.

### 5. Configure Jenkins Credentials

| Credential ID | Type | Used For |
|---|---|---|
| `docker` | Username/Password | Docker Hub image push |
| `github-creds` | Username/Password | Kustomize commits + git tagging |
| `NVD_KEY` | Secret Text | OWASP Dependency-Check NVD API |
| `SonarQube` | Server config | `withSonarQubeEnv` integration |
| `aws-access-key-id` | Secret Text | AWS ECR (when enabled) |
| `aws-secret-access-key` | Secret Text | AWS ECR (when enabled) |

Point Jenkins at this repository with the root `Jenkinsfile`. Configure a GitHub webhook to trigger the pipeline on push.

> See [`infra/jenkins/README.md`](./infra/jenkins/README.md) for the full Jenkins setup guide.

---

## Roadmap

- [ ] Enable ECR push (currently commented out in favour of Docker Hub for dev)
- [ ] DAST integration — OWASP ZAP as a post-deployment pipeline stage
- [ ] Falco runtime threat detection for anomalous container behaviour
- [ ] HashiCorp Vault for dynamic secrets management
- [ ] Cosign image signing + Kubernetes admission verification
- [ ] Automated staging → prod promotion via pull request workflow
- [ ] SLA-based Grafana alerting with PagerDuty integration

---

## Section READMEs

| Section | Description |
|---|---|
| [`app/README.md`](./app/microservices-demo/README.md) | Online Boutique microservices overview |
| [`infra/README.md`](./infra/README.md) | Terraform modules and AWS infrastructure |
| [`gitops/README.md`](./gitops/README.md) | ArgoCD setup and GitOps workflow |
| [`infra/monitoring/README.md`](./infra/monitoring/README.md) | Prometheus & Grafana stack |
| [`infra/jenkins/README.md`](./infra/jenkins/README.md) | Jenkins setup and credential configuration |

---
