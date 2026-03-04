# GitOps — ArgoCD Deployment

This document covers the GitOps workflow, ArgoCD setup, and multi-environment deployment strategy for the Online Boutique DevSecOps project.

---

## Table of Contents

- [GitOps — ArgoCD Deployment](#gitops--argocd-deployment)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [How GitOps Works Here](#how-gitops-works-here)
  - [Repository Structure](#repository-structure)
  - [Environments](#environments)
  - [ArgoCD Setup](#argocd-setup)
    - [Install ArgoCD](#install-argocd)
    - [Access the UI](#access-the-ui)
    - [Bootstrap Applications](#bootstrap-applications)
    - [Example ArgoCD Application Manifest](#example-argocd-application-manifest)
  - [Image Tagging Strategy](#image-tagging-strategy)
    - [Dev — Git SHA](#dev--git-sha)
    - [Staging — Semver](#staging--semver)
    - [Prod — Exact Semver](#prod--exact-semver)
  - [Deploying a Change](#deploying-a-change)
    - [Normal Flow (automated)](#normal-flow-automated)
    - [Manual Sync via ArgoCD CLI](#manual-sync-via-argocd-cli)
  - [Manual Sync \& Rollback](#manual-sync--rollback)
    - [View deployment history](#view-deployment-history)
    - [Rollback to a previous revision](#rollback-to-a-previous-revision)
    - [Rollback via Git](#rollback-via-git)
  - [Troubleshooting](#troubleshooting)

---

## Overview

This project uses a **GitOps deployment model** powered by ArgoCD. The Git repository is the single source of truth for the cluster state — ArgoCD continuously reconciles what is in `gitops/` with what is running in EKS.

Jenkins **never pushes to Kubernetes directly**. It only updates image tags in Git. ArgoCD detects the change and handles the actual deployment.

**Benefits:**
- Every deployment is a Git commit — auditable, reviewable, and reversible
- Cluster state is always declaratively defined — no configuration drift
- Rollback is `git revert` — no special tooling or runbooks required
- ArgoCD works independently of Jenkins — cluster stays healthy even if CI is down

---

## How GitOps Works Here

```
Developer pushes code
        │
        ▼
Jenkins CI runs all security gates
        │
        ▼
Jenkins builds and pushes Docker image
        │
        ▼
Jenkins runs: kustomize edit set image <new-tag>
Jenkins commits: gitops/k8s/overlays/<env>/kustomization.yaml [skip ci]
        │
        ▼
ArgoCD polls Git (every 3 minutes) or receives webhook
        │
        ▼
ArgoCD detects diff between Git state and live cluster
        │
        ▼
ArgoCD syncs: applies updated Kustomize overlay to EKS
        │
        ▼
Kubernetes performs rolling update
        │
        ▼
ArgoCD health checks pass → sync complete
Deployment recorded in ArgoCD history
```

---

## Repository Structure

```
gitops/
└── k8s/
    ├── base/                          # Shared base manifests (all environments)
    │   ├── adservice.yaml
    │   ├── cartservice.yaml
    │   ├── checkoutservice.yaml
    │   ├── currencyservice.yaml
    │   ├── emailservice.yaml
    │   ├── frontend.yaml
    │   ├── loadgenerator.yaml
    │   ├── paymentservice.yaml
    │   ├── productcatalogservice.yaml
    │   ├── recommendationservice.yaml
    │   ├── shippingservice.yaml
    │   └── kustomization.yaml
    │
    └── overlays/
        ├── dev/
        │   └── kustomization.yaml     # Image tags pinned to git SHA
        ├── staging/
        │   └── kustomization.yaml     # Image tags pinned to semver
        └── prod/
            └── kustomization.yaml     # Image tags pinned to exact semver
```

---

## Environments

Three environments are managed as Kustomize overlays. Each has an independent ArgoCD Application pointing to its overlay path.

| Environment | Tag Strategy | Sync Policy | Purpose |
|---|---|---|---|
| **dev** | `git-sha` (e.g. `c7bcc53e`) | Auto-sync | Deploys on every successful CI build |
| **staging** | `semver` (e.g. `1.4.2`) | Auto-sync | Stable named releases for QA testing |
| **prod** | `semver` (e.g. `1.4.2`) | Manual or auto | Exact, auditable production deployments |

---

## ArgoCD Setup

### Install ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Access the UI

```bash
# Port-forward to access locally
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Navigate to `https://localhost:8080` and login with `admin` + the password above.

### Bootstrap Applications

Apply all ArgoCD Application manifests to register each environment:

```bash
kubectl apply -f gitops/applications/
```

This creates three ArgoCD Applications: `online-boutique-dev`, `online-boutique-staging`, `online-boutique-prod`.

### Example ArgoCD Application Manifest

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: online-boutique-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/alexzhenyul/online-boutique-devsecops.git
    targetRevision: main
    path: gitops/k8s/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: online-boutique-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## Image Tagging Strategy

Jenkins updates each overlay with a different tag depending on the environment:

### Dev — Git SHA
```yaml
# gitops/k8s/overlays/dev/kustomization.yaml
images:
  - name: alexzhenyul/online-boutique-dev
    newTag: frontend-c7bcc53e   # ← updated by Jenkins on every build
```
Every successful build immediately deploys to dev — useful for rapid feedback.

### Staging — Semver
```yaml
# gitops/k8s/overlays/staging/kustomization.yaml
images:
  - name: alexzhenyul/online-boutique-dev
    newTag: frontend-1.4.2      # ← stable, named release
```
Staging always runs a version that can be identified, tested, and referenced.

### Prod — Exact Semver
```yaml
# gitops/k8s/overlays/prod/kustomization.yaml
images:
  - name: alexzhenyul/online-boutique-dev
    newTag: frontend-1.4.2      # ← identical to staging; promotes tested version
```
Production only ever runs an exact, previously-tested semver image.

---

## Deploying a Change

### Normal Flow (automated)

1. Push a commit to a microservice source directory
2. Jenkins runs security gates, builds, and scans the image
3. Jenkins commits updated image tags to `gitops/k8s/overlays/`
4. ArgoCD detects the Git change and syncs automatically

### Manual Sync via ArgoCD CLI

```bash
# Install ArgoCD CLI
brew install argocd  # macOS

# Login
argocd login localhost:8080

# Trigger a manual sync
argocd app sync online-boutique-dev
argocd app sync online-boutique-staging
argocd app sync online-boutique-prod

# Check application status
argocd app get online-boutique-prod
```

---

## Manual Sync & Rollback

### View deployment history

```bash
argocd app history online-boutique-prod
```

### Rollback to a previous revision

```bash
# Roll back to revision ID 5
argocd app rollback online-boutique-prod 5
```

### Rollback via Git

Since every deployment is a Git commit, you can also roll back by reverting the manifest commit:

```bash
git log --oneline gitops/k8s/overlays/prod/kustomization.yaml

# Revert the last manifest update
git revert <commit-sha> --no-edit
git push origin main
# ArgoCD will automatically sync the reverted state
```

---

## Troubleshooting

**ArgoCD shows `OutOfSync` but won't auto-sync**
→ Check if `selfHeal: true` is set in the Application's `syncPolicy`. If not, trigger a manual sync.

**ArgoCD shows `Degraded` after sync**
→ The new pods are failing health checks. Run `kubectl describe pod <pod> -n online-boutique-<env>` to see the error. The previous version is still running — check image tag is correct in the overlay.

**Image pull error: `ImagePullBackOff`**
→ The image tag in `kustomization.yaml` doesn't exist in Docker Hub. Verify the Jenkins build pushed successfully, and the tag in the overlay matches exactly.

**Changes to `gitops/` not triggering ArgoCD**
→ ArgoCD polls every 3 minutes by default. To get instant sync, configure a GitHub webhook: in ArgoCD go to **Settings → Repositories** and note the webhook URL.

**`[skip ci]` commits are still triggering Jenkins**
→ Ensure Jenkins is configured to check commit messages. The pipeline reads `git log -1 --pretty=%B HEAD` and exits early with `NOT_BUILT` when it sees `[skip ci]`.