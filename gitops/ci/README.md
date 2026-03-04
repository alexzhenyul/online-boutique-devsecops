# Jenkins CI — Setup & Configuration

This document covers the Jenkins setup, pipeline configuration, required credentials, and tool installations for the Online Boutique DevSecOps CI pipeline.

---

## Table of Contents

- [Jenkins CI — Setup \& Configuration](#jenkins-ci--setup--configuration)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Infrastructure](#infrastructure)
  - [Required Tools](#required-tools)
    - [Gitleaks](#gitleaks)
    - [SonarQube Scanner](#sonarqube-scanner)
    - [OWASP Dependency-Check](#owasp-dependency-check)
    - [Trivy](#trivy)
    - [Hadolint](#hadolint)
    - [Kustomize](#kustomize)
    - [Docker](#docker)
  - [Jenkins Plugins](#jenkins-plugins)
  - [Credentials Configuration](#credentials-configuration)
    - [SonarQube Server Configuration](#sonarqube-server-configuration)
    - [GitHub Webhook](#github-webhook)
  - [Pipeline Overview](#pipeline-overview)
  - [Stage Reference](#stage-reference)
    - [Detect Changed Microservice](#detect-changed-microservice)
    - [Gitleaks](#gitleaks-1)
    - [SonarQube SAST](#sonarqube-sast)
    - [OWASP Dependency-Check](#owasp-dependency-check-1)
    - [Trivy FS \& Image Scans](#trivy-fs--image-scans)
    - [Docker Build](#docker-build)
    - [Update Kustomize Manifest](#update-kustomize-manifest)
  - [Scan Artifacts](#scan-artifacts)
  - [Email Notifications](#email-notifications)
  - [Troubleshooting](#troubleshooting)

---

## Overview

Jenkins is the CI engine for this project. It runs on an EC2 instance (provisioned via Terraform) and is triggered by a GitHub webhook on every push to `main`.

The pipeline is fully defined in the root [`Jenkinsfile`](../../Jenkinsfile) — no manual stage configuration in the Jenkins UI. Every run produces a versioned, security-scanned Docker image and updates the GitOps manifests for ArgoCD to pick up.

---

## Infrastructure

Jenkins runs on an EC2 instance provisioned via Terraform in `infra/jenkins/`.

| Setting | Value |
|---|---|
| Region | `ap-southeast-4` (Melbourne) |
| Instance type | `t3.medium` (recommended minimum) |
| OS | Ubuntu 22.04 LTS |
| IAM role | Scoped to ECR push + SSM access |

To provision:

```bash
cd infra/jenkins
terraform init
terraform apply
```

---

## Required Tools

The following tools must be installed on the Jenkins EC2 instance:

### Gitleaks
```bash
# Install via binary release
GITLEAKS_VERSION=8.18.4
curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz \
  | tar -xz -C /usr/local/bin gitleaks
gitleaks version
```

### SonarQube Scanner
```bash
SONAR_VERSION=5.0.1.3006
wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_VERSION}-linux.zip
unzip sonar-scanner-cli-${SONAR_VERSION}-linux.zip -d /opt/
ln -s /opt/sonar-scanner-${SONAR_VERSION}-linux/bin/sonar-scanner /usr/local/bin/sonar-scanner
sonar-scanner --version
```

### OWASP Dependency-Check
```bash
DC_VERSION=9.0.9
wget https://github.com/jeremylong/DependencyCheck/releases/download/v${DC_VERSION}/dependency-check-${DC_VERSION}-release.zip
unzip dependency-check-${DC_VERSION}-release.zip -d /opt/
ln -s /opt/dependency-check/bin/dependency-check.sh /usr/local/bin/dependency-check

# Pre-create data directory for NVD cache
mkdir -p /var/lib/jenkins/dependency-check-data
chown -R jenkins:jenkins /var/lib/jenkins/dependency-check-data
```

### Trivy
```bash
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sh -s -- -b /usr/local/bin
trivy --version
```

### Hadolint
```bash
HADOLINT_VERSION=2.12.0
wget https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64 \
  -O /usr/local/bin/hadolint
chmod +x /usr/local/bin/hadolint
hadolint --version
```

### Kustomize
```bash
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
mv kustomize /usr/local/bin/
kustomize version
```

### Docker
```bash
curl -fsSL https://get.docker.com | sh
usermod -aG docker jenkins
# Restart Jenkins after this
```

---

## Jenkins Plugins

Install the following plugins via **Manage Jenkins → Plugins**:

| Plugin | Purpose |
|---|---|
| Pipeline | Core declarative pipeline support |
| Git | Repository checkout |
| SonarQube Scanner | `withSonarQubeEnv` + quality gate integration |
| OWASP Dependency-Check | Report publishing via `publishHTML` |
| HTML Publisher | Publish scan HTML reports to build |
| Email Extension (Email-ext) | HTML email notifications |
| Credentials Binding | `withCredentials` block support |
| Docker Pipeline | Docker build/push in pipeline |
| AWS Credentials | AWS key management |

---

## Credentials Configuration

Navigate to **Manage Jenkins → Credentials → System → Global credentials** and add:

| Credential ID | Type | Value |
|---|---|---|
| `docker` | Username/Password | Docker Hub username + access token |
| `github-creds` | Username/Password | GitHub username + personal access token (repo + write scope) |
| `NVD_KEY` | Secret Text | NVD API key from [nvd.nist.gov/developers/request-an-api-key](https://nvd.nist.gov/developers/request-an-api-key) |
| `aws-access-key-id` | Secret Text | AWS access key (for ECR, when enabled) |
| `aws-secret-access-key` | Secret Text | AWS secret key (for ECR, when enabled) |

### SonarQube Server Configuration

Navigate to **Manage Jenkins → System → SonarQube Servers**:

- **Name:** `SonarQube` ← must match `withSonarQubeEnv('SonarQube')` in Jenkinsfile
- **Server URL:** `http://<your-sonarqube-host>:9000`
- **Server authentication token:** Create a token in SonarQube under **My Account → Security**

### GitHub Webhook

In your GitHub repository, go to **Settings → Webhooks → Add webhook**:

- **Payload URL:** `http://<jenkins-host>:8080/github-webhook/`
- **Content type:** `application/json`
- **Events:** `Just the push event`

---

## Pipeline Overview

```
git push
    │
    ▼
┌─────────────────────────────────────────────────────┐
│ Stage 1: Detect Changed Microservice                │
│  • Diffs HEAD~1..HEAD for src/ changes              │
│  • Auto-detects language (Go/Python/Java/C#/Node)   │
│  • Calculates next semver from git tags             │
│  • Checks commit message for conventional prefix    │
│  • Exits early (NOT_BUILT) if no service changed    │
└────────────────────┬────────────────────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │ Stage 2: Gitleaks               │ ◄─ BLOCKS on any secret found
    └────────────────┬────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │ Stage 3: SonarQube SAST         │ ◄─ Language-aware scan
    │ Stage 4: Quality Gate           │ ◄─ BLOCKS if gate fails
    └────────────────┬────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │ Stage 5: OWASP Dependency-Check │ ◄─ BLOCKS on CVSS ≥ 8.0
    └────────────────┬────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │ Stage 6: Trivy FS Scan          │ ◄─ BLOCKS on HIGH/CRITICAL
    └────────────────┬────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │ Stage 7: Hadolint               │   (non-blocking, logged)
    └────────────────┬────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │ Stage 8: Docker Build           │
    └────────────────┬────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │ Stage 9: Trivy Image Scan       │ ◄─ BLOCKS on HIGH/CRITICAL
    └────────────────┬────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │ Stage 10: Push to Docker Hub    │
    └────────────────┬────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │ Stage 11: Update Kustomize      │
    │  • dev  → git SHA               │
    │  • staging → semver             │
    │  • prod → semver                │
    └────────────────┬────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │ Stage 12: Tag Git Commit        │
    │  • Pushes <service>/<semver>    │
    └────────────────┬────────────────┘
                     │
    ┌────────────────▼────────────────┐
    │ post: Email Notification        │
    └─────────────────────────────────┘
```

---

## Stage Reference

### Detect Changed Microservice

- Compares `HEAD~1` to `HEAD` for changes under `app/microservices-demo/src/`
- Detects language by searching for `pom.xml`, `go.mod`, `package.json`, `requirements.txt`, `*.csproj`
- Reads commit message to determine semver bump (`feat:` → minor, `BREAKING CHANGE:` → major, all else → patch)
- Calculates new version from the latest `<service>/*` git tag
- Sets `env.MICROSERVICE`, `env.LANGUAGE`, `env.SEMVER`, `env.IMAGE_TAG`, `env.GIT_SHORT`

### Gitleaks

- Scans `app/microservices-demo/src/<service>/` with `--no-git` (directory scan)
- Reports saved to `gitleaks-report.json`
- Exit code `1` from Gitleaks → pipeline fails immediately

### SonarQube SAST

Language-specific behaviour:

| Language | Extra Steps |
|---|---|
| Java (Maven) | Runs `mvn clean compile` first; passes `sonar.java.binaries` |
| Java (Gradle) | Runs `./gradlew classes`; passes `sonar.java.binaries` |
| Go | Source scan only |
| Node.js | Passes LCOV coverage path |
| Python | Sets `sonar.python.version=3` |
| C# | Source scan only |

Quality gate waits up to **5 minutes** for SonarQube to respond. Pipeline aborts if gate fails.

### OWASP Dependency-Check

- Requires NVD API key stored as `NVD_KEY` credential
- NVD data cached in `/var/lib/jenkins/dependency-check-data` to avoid re-downloading on every build
- Fails on CVSS score ≥ 8.0
- Publishes HTML report via Jenkins HTML Publisher plugin

### Trivy FS & Image Scans

- Both scans use `--severity HIGH,CRITICAL --exit-code 1`
- Image scan also uses `--ignore-unfixed` (only fails on CVEs that have a fix available)
- Reports saved as JSON artifacts

### Docker Build

- BuildKit enabled (`DOCKER_BUILDKIT=1`)
- OCI labels applied: `version`, `revision`, `created`, `service`
- Three tags built simultaneously: `semver`, `git-sha`, `latest`
- Targets `linux/amd64` platform explicitly

### Update Kustomize Manifest

- Commits back to `main` with `[skip ci]` to prevent pipeline re-trigger
- Updates three overlays: `dev` (SHA), `staging` (semver), `prod` (semver)
- Skips commit if kustomization files are already up to date (idempotent)

---

## Scan Artifacts

Every build archives the following to `<build-url>/artifact/`:

| File | Tool | Format |
|---|---|---|
| `gitleaks-report.json` | Gitleaks | JSON |
| `reports/dependency-check-report.html` | OWASP | HTML (viewable in Jenkins) |
| `reports/dependency-check-report.json` | OWASP | JSON |
| `trivy-fs-report.json` | Trivy | JSON |
| `hadolint-report.json` | Hadolint | JSON |
| `trivy-image-report.json` | Trivy | JSON |

---

## Email Notifications

Configured via `emailext` in the `post { always { } }` block. Sent to `EMAIL_RECIPIENTS` on every build regardless of result.

Email includes:
- Color-coded header (green / amber / red based on build result)
- Build summary table (service, version, SHA, branch, ECR image, duration)
- Per-stage status with notes
- Direct artifact download links
- Full Jenkins build URL

To configure the SMTP server: **Manage Jenkins → System → Extended E-mail Notification**

---

## Troubleshooting

**Pipeline exits as `NOT_BUILT`**
→ No files changed under `app/microservices-demo/src/`. Push a change to a service's source directory.

**OWASP scan is very slow on first run**
→ The NVD database is being downloaded for the first time. It caches to `/var/lib/jenkins/dependency-check-data` — subsequent runs are much faster.

**SonarQube quality gate times out**
→ Check that the SonarQube webhook is configured: in SonarQube go to **Administration → Configuration → Webhooks** and add `http://<jenkins-host>:8080/sonarqube-webhook/`.

**`kustomize: command not found`**
→ Kustomize is not installed or not on the Jenkins PATH. Verify with `which kustomize` as the `jenkins` user.

**Docker permission denied**
→ The `jenkins` user is not in the `docker` group. Run `usermod -aG docker jenkins` and restart Jenkins.