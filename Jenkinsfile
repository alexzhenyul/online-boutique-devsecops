pipeline {
    agent any

    environment {
        // AWS & ECR
        AWS_REGION      = 'ap-southeast-4'
        ECR_REGISTRY    = '253343486660.dkr.ecr.ap-southeast-4.amazonaws.com'
        ECR_REPO_PREFIX = 'online-boutique'
        
        // OWASP
        DC_DATA_DIR     = '/var/lib/jenkins/dependency-check-data'

        // EMAIL
        EMAIL_RECIPIENTS = 'zhenyu.alexl@gmail,lzyx0207@gmail.com'
    }

    stages {

        stage('Detect Changed Microservice') {
            steps {
                script {
                    def changedFiles = sh(
                        script: "git diff --name-only HEAD~1 HEAD",
                        returnStdout: true
                    ).trim()

                    echo "=== Changed Files ==="
                    echo "${changedFiles}"

                    def detectedService = ''
                    changedFiles.split('\n').each { file ->
                        def match = file =~ /^app\/microservices-demo\/src\/([^\/]+)\/.+/
                        if (match && !detectedService) {
                            detectedService = match[0][1]
                        }
                    }

                    if (!detectedService) {
                        echo "No microservice source changes detected. Skipping."
                        currentBuild.result = 'NOT_BUILT'
                        return
                    }

                    env.MICROSERVICE = detectedService
                    env.SERVICE_PATH = "app/microservices-demo/src/${detectedService}"
                    env.GIT_SHORT    = env.GIT_COMMIT.take(8)

                    // ── Conventional Commits: auto-detect bump type ───────────
                    def commitMsg = sh(
                        script: "git log -1 --pretty=%B HEAD",
                        returnStdout: true
                    ).trim()

                    echo "=== Commit Message ==="
                    echo "${commitMsg}"

                    def bumpType = 'patch' // default

                    if (commitMsg.contains('BREAKING CHANGE:') || commitMsg =~ /^[a-z]+(\(.+\))?!:/) {
                        bumpType = 'major'
                    } else if (commitMsg =~ /^feat(\(.+\))?:/) {
                        bumpType = 'minor'
                    }
                    // fix:, perf:, refactor:, chore:, docs:, style:, test: → patch

                    echo "Detected bump type: ${bumpType}"

                    // ── Semver Calculation ────────────────────────────────────
                    def rawTag = sh(
                        script: """
                            git tag --list "${detectedService}/*" \
                                | sort -t/ -k2 -V \
                                | tail -1 \
                                | awk -F/ '{print \$2}'
                        """,
                        returnStdout: true
                    ).trim()

                    if (!rawTag) rawTag = '0.0.0'

                    def (maj, min, pat) = rawTag.tokenize('.').collect { it.toInteger() }

                    switch (bumpType) {
                        case 'major': maj++; min = 0; pat = 0; break
                        case 'minor': min++; pat = 0;          break
                        default:      pat++;                    break
                    }

                    env.SEMVER    = "${maj}.${min}.${pat}"
                    env.IMAGE_TAG = env.SEMVER

                    def base             = "${ECR_REGISTRY}/${ECR_REPO_PREFIX}/${detectedService}"
                    env.ECR_IMAGE        = "${base}:${env.SEMVER}"
                    env.ECR_IMAGE_SHA    = "${base}:${env.GIT_SHORT}"
                    env.ECR_IMAGE_LATEST = "${base}:latest"

                    echo """
                    ╔══════════════════════════════════════════════╗
                    ║  Detected microservice : ${env.MICROSERVICE}
                    ║  Commit message type   : ${bumpType}
                    ║  Previous version      : ${rawTag}
                    ║  New version           : ${env.SEMVER}
                    ║  Git SHA               : ${env.GIT_SHORT}
                    ╚══════════════════════════════════════════════╝
                    """
                }
            }
        }

        stage('Secret Scanning - Gitleaks') {
            when {
                expression { env.MICROSERVICE != null && env.MICROSERVICE != '' }
            }
            steps {
                script {
                    echo "Running Gitleaks on: app/microservices-demo/src/${env.MICROSERVICE}"

                    def exitCode = sh(
                        script: """
                            gitleaks detect \
                                --source=app/microservices-demo/src/${env.MICROSERVICE} \
                                --report-format=json \
                                --report-path=gitleaks-report.json \
                                --exit-code=1 \
                                --no-git
                        """,
                        returnStatus: true
                    )

                    if (exitCode == 1) {
                        error "Gitleaks found secrets! Check gitleaks-report.json for details."
                    } else {
                        echo "No secrets found in ${env.MICROSERVICE}"
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('SAST - SonarQube Analysis') {
            when {
                expression { env.MICROSERVICE != null && env.MICROSERVICE != '' }
            }
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh """
                        sonar-scanner \
                            -Dsonar.projectKey=${env.MICROSERVICE} \
                            -Dsonar.projectName=${env.MICROSERVICE} \
                            -Dsonar.sources=app/microservices-demo/src/${env.MICROSERVICE} \
                            -Dsonar.projectVersion=${env.GIT_COMMIT.take(8)}
                    """
                }
            }
        }

        stage('SonarQube Quality Gate') {
            when {
                expression { env.MICROSERVICE != null && env.MICROSERVICE != '' }
            }
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('SCA - OWASP Dependency Check') {
            when {
                expression { env.MICROSERVICE != null && env.MICROSERVICE != '' }
            }
            steps {
                withCredentials([string(credentialsId: 'NVD_KEY', variable: 'NVD_KEY')]) {
                    script {
                        echo "Running OWASP Dependency Check on: app/microservices-demo/src/${env.MICROSERVICE}"

                        sh "mkdir -p reports"

                        def exitCode = sh(
                            script: """
                                dependency-check \
                                    --scan app/microservices-demo/src/${env.MICROSERVICE} \
                                    --project ${env.MICROSERVICE} \
                                    --format HTML \
                                    --format JSON \
                                    --out reports/ \
                                    --failOnCVSS 8 \
                                    --data /var/lib/jenkins/dependency-check-data \
                                    --nvdApiKey \$NVD_KEY \
                                    --nvdApiDelay 6000 \
                                    --nvdMaxRetryCount 5
                            """,
                            returnStatus: true
                        )

                        if (exitCode != 0) {
                            error "OWASP Dependency Check found vulnerabilities with CVSS ≥ 8.0!"
                        } else {
                            echo "No critical vulnerabilities found in ${env.MICROSERVICE}"
                        }
                    }
                }  // ← closes withCredentials
            }
            post {
                always {
                    publishHTML(target: [
                        allowMissing         : true,
                        alwaysLinkToLastBuild: true,
                        keepAll              : true,
                        reportDir            : 'reports',
                        reportFiles          : 'dependency-check-report.html',
                        reportName           : 'OWASP Dependency Check Report'
                    ])
                    archiveArtifacts artifacts: 'reports/dependency-check-report.json', allowEmptyArchive: true
                }
            }
        }  

        stage('Trivy FS Scan') {
            when {
                expression { env.MICROSERVICE != null && env.MICROSERVICE != '' }
            }
            steps {
                script {
                    echo "🔍 Running Trivy filesystem scan on: app/microservices-demo/src/${env.MICROSERVICE}"

                    def exitCode = sh(
                        script: """
                            trivy fs \
                                --severity HIGH,CRITICAL \
                                --exit-code 1 \
                                --format json \
                                --output trivy-fs-report.json \
                                app/microservices-demo/src/${env.MICROSERVICE}
                        """,
                        returnStatus: true
                    )

                    if (exitCode == 1) {
                        error "Trivy found HIGH/CRITICAL vulnerabilities in filesystem!"
                    } else {
                        echo "No HIGH/CRITICAL vulnerabilities found in ${env.MICROSERVICE} filesystem"
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-fs-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('Hadolint Dockerfile Scan') {
            when {
                expression { env.MICROSERVICE != null && env.MICROSERVICE != '' }
            }
            steps {
                script {
                    echo "🔍 Running Hadolint on: app/microservices-demo/src/${env.MICROSERVICE}/Dockerfile"

                    def exitCode = sh(
                        script: """
                            hadolint \
                                --format json \
                                app/microservices-demo/src/${env.MICROSERVICE}/Dockerfile \
                                > hadolint-report.json
                        """,
                        returnStatus: true
                    )

                    if (exitCode != 0) {
                        echo "Hadolint found Dockerfile issues - check hadolint-report.json"
                        // Use 'error' instead of echo if you want to FAIL the pipeline
                    } else {
                        echo "Dockerfile passed Hadolint checks"
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'hadolint-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('Build Docker Image') {
            when {
                expression { env.MICROSERVICE != null && env.MICROSERVICE != '' }
            }
            steps {
                script {
                    echo """
                    ╔══════════════════════════════════════════════╗
                    ║  Building Docker image
                    ║  Service  : ${env.MICROSERVICE}
                    ║  Semver   : ${env.SEMVER}
                    ║  Git SHA  : ${env.GIT_SHORT}
                    ╚══════════════════════════════════════════════╝
                    """

                    sh """
                        export DOCKER_BUILDKIT=1

                        docker build \
                            --build-arg BUILDPLATFORM=linux/amd64 \
                            --build-arg TARGETOS=linux \
                            --build-arg TARGETARCH=amd64 \
                            --label "org.opencontainers.image.version=${env.SEMVER}" \
                            --label "org.opencontainers.image.revision=${env.GIT_COMMIT}" \
                            --label "org.opencontainers.image.created=\$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                            --label "org.opencontainers.image.source=${env.GIT_URL}" \
                            --label "service=${env.MICROSERVICE}" \
                            -t ${env.ECR_IMAGE} \
                            -t ${env.ECR_IMAGE_SHA} \
                            -t ${env.ECR_IMAGE_LATEST} \
                            ${env.SERVICE_PATH}
                    """

                    echo "Built tags:"
                    echo "  ${env.ECR_IMAGE}        ← semver (primary)"
                    echo "  ${env.ECR_IMAGE_SHA}    ← git sha (traceability)"
                    echo "  ${env.ECR_IMAGE_LATEST} ← latest (convenience)"
                }
            }
        }

        stage('Trivy Image Scan') {
            when {
                expression { env.MICROSERVICE != null && env.MICROSERVICE != '' }
            }
            steps {
                script {
                    echo "🔍 Running Trivy image scan on: ${env.ECR_IMAGE}"

                    def exitCode = sh(
                        script: """
                            trivy image \
                                --severity HIGH,CRITICAL \
                                --exit-code 1 \
                                --format json \
                                --output trivy-image-report.json \
                                --no-progress \
                                ${env.ECR_IMAGE}
                        """,
                        returnStatus: true
                    )

                    if (exitCode == 1) {
                        error "Trivy found HIGH/CRITICAL vulnerabilities in image: ${env.ECR_IMAGE}!"
                    } else {
                        echo "No HIGH/CRITICAL vulnerabilities found in image: ${env.ECR_IMAGE}"
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-image-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('Push to ECR') {
            when {
                expression { env.MICROSERVICE != null && env.MICROSERVICE != '' }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id',     variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    script {
                        sh """
                            export AWS_ACCESS_KEY_ID=\$AWS_ACCESS_KEY_ID
                            export AWS_SECRET_ACCESS_KEY=\$AWS_SECRET_ACCESS_KEY
                            export AWS_DEFAULT_REGION=${AWS_REGION}

                            aws ecr get-login-password --region ${AWS_REGION} | \
                                docker login --username AWS --password-stdin ${ECR_REGISTRY}

                            docker push ${env.ECR_IMAGE}
                        """

                        // Only push additional tags if they were set by semver logic
                        if (env.ECR_IMAGE_SHA) {
                            sh "docker push ${env.ECR_IMAGE_SHA}"
                            echo "Pushed SHA tag: ${env.ECR_IMAGE_SHA}"
                        }

                        if (env.ECR_IMAGE_LATEST) {
                            sh "docker push ${env.ECR_IMAGE_LATEST}"
                            echo "Pushed latest tag: ${env.ECR_IMAGE_LATEST}"
                        }

                        echo "Successfully pushed: ${env.ECR_IMAGE}"
                    }
                }
            }
        }

        stage('Tag Git Commit') {
            when {
                expression { env.MICROSERVICE != null && env.MICROSERVICE != '' }
            }
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: 'System-Global-github-creds-github-creds',
                        usernameVariable: 'GIT_USER',
                        passwordVariable: 'GIT_TOKEN'
                    )]) {
                        sh """
                            git config user.email "jenkins@ci"
                            git config user.name  "Jenkins"

                            git remote set-url origin https://\${GIT_USER}:\${GIT_TOKEN}@github.com/${GIT_ORG}/${GIT_REPO}.git

                            git tag "${env.MICROSERVICE}/${env.SEMVER}"
                            git push origin "${env.MICROSERVICE}/${env.SEMVER}"
                        """
                        echo "Git tag created: ${env.MICROSERVICE}/${env.SEMVER}"
                    }
                }
            }
        }

        stage('Print Result') {
            steps {
                script {
                    if (!env.MICROSERVICE) {
                        echo "No microservice was detected."
                    } else {
                        echo """
                        ╔══════════════════════════════════════════════════════════════╗
                        ║  Pipeline complete
                        ║  Service  : ${env.MICROSERVICE}
                        ║  Version  : ${env.SEMVER}  (${params.VERSION_BUMP} bump)
                        ║  Git SHA  : ${env.GIT_SHORT}
                        ║  Images pushed to ECR:
                        ║    • ${env.ECR_IMAGE}
                        ║    • ${env.ECR_IMAGE_SHA}
                        ║    • ${env.ECR_IMAGE_LATEST}
                        ╚══════════════════════════════════════════════════════════════╝
                        """
                    }
                }
            }

        }
    }
        post {
        always {
            script {
                // ── Collect stage results ─────────────────────────────────
                def skipScans = env.SKIP_SCANS == 'true'

                def stageStatus = { String stageName ->
                    def result = currentBuild.rawBuild.getAction(
                        org.jenkinsci.plugins.workflow.job.views.FlowGraphAction
                    )
                    // Simplified: use env flags we set per stage
                    return '✅'
                }

                def scanMode   = skipScans ? 'QUICK MODE (scans skipped)' : 'FULL MODE (all scans ran)'
                def buildColor = currentBuild.result == 'SUCCESS' ? '#36a64f' :
                                 currentBuild.result == 'UNSTABLE' ? '#f0ad4e' : '#dc3545'
                def buildIcon  = currentBuild.result == 'SUCCESS' ? '✅' :
                                 currentBuild.result == 'UNSTABLE' ? '⚠️' : '❌'

                def microservice = env.MICROSERVICE ?: 'N/A'
                def semver       = env.SEMVER       ?: 'N/A'
                def gitShort     = env.GIT_SHORT    ?: 'N/A'
                def ecrImage     = env.ECR_IMAGE    ?: 'N/A'

                def emailBody = """
<!DOCTYPE html>
<html>
<body style="font-family: Arial, sans-serif; font-size: 14px; color: #333;">

  <!-- Header -->
  <div style="background-color: ${buildColor}; padding: 16px; border-radius: 6px 6px 0 0;">
    <h2 style="margin: 0; color: white;">
      ${buildIcon} Jenkins Pipeline: ${currentBuild.result ?: 'IN PROGRESS'}
    </h2>
    <p style="margin: 4px 0 0; color: white; opacity: 0.9;">
      ${env.JOB_NAME} — Build #${env.BUILD_NUMBER}
    </p>
  </div>

  <!-- Build Summary -->
  <div style="background: #f8f9fa; padding: 16px; border: 1px solid #dee2e6;">
    <h3 style="margin-top: 0;">📋 Build Summary</h3>
    <table style="border-collapse: collapse; width: 100%;">
      <tr><td style="padding: 4px 12px 4px 0; font-weight: bold; width: 180px;">Microservice</td><td>${microservice}</td></tr>
      <tr><td style="padding: 4px 12px 4px 0; font-weight: bold;">Version</td><td>${semver}</td></tr>
      <tr><td style="padding: 4px 12px 4px 0; font-weight: bold;">Git Commit</td><td>${gitShort}</td></tr>
      <tr><td style="padding: 4px 12px 4px 0; font-weight: bold;">Branch</td><td>${env.GIT_BRANCH ?: 'main'}</td></tr>
      <tr><td style="padding: 4px 12px 4px 0; font-weight: bold;">ECR Image</td><td><code style="font-size:12px;">${ecrImage}</code></td></tr>
      <tr><td style="padding: 4px 12px 4px 0; font-weight: bold;">Scan Mode</td><td>${scanMode}</td></tr>
      <tr><td style="padding: 4px 12px 4px 0; font-weight: bold;">Duration</td><td>${currentBuild.durationString}</td></tr>
      <tr><td style="padding: 4px 12px 4px 0; font-weight: bold;">Build URL</td>
          <td><a href="${env.BUILD_URL}">${env.BUILD_URL}</a></td></tr>
    </table>
  </div>

  <!-- Stage Results -->
  <div style="padding: 16px; border: 1px solid #dee2e6; border-top: none;">
    <h3 style="margin-top: 0;">🔍 Stage Results</h3>
    <table style="border-collapse: collapse; width: 100%; border: 1px solid #dee2e6;">
      <thead>
        <tr style="background: #343a40; color: white;">
          <th style="padding: 8px 12px; text-align: left;">Stage</th>
          <th style="padding: 8px 12px; text-align: left;">Status</th>
          <th style="padding: 8px 12px; text-align: left;">Notes</th>
        </tr>
      </thead>
      <tbody>
        <tr style="background: #fff;">
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">Detect Changed Microservice</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${microservice != 'N/A' ? 'Passed' : 'Skipped'}</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${microservice != 'N/A' ? "Detected: ${microservice}" : 'No changes found'}</td>
        </tr>
        <tr style="background: #f8f9fa;">
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">Secret Scanning (Gitleaks)</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '⏭ Skipped' : (currentBuild.result != 'FAILURE' ? 'No secrets found' : 'Failed')}</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '[skip-scans] flag set' : 'See gitleaks-report.json'}</td>
        </tr>
        <tr style="background: #fff;">
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">SAST - SonarQube</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '⏭ Skipped' : (currentBuild.result != 'FAILURE' ? 'Passed' : 'Failed')}</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '[skip-scans] flag set' : "Project key: ${microservice}"}</td>
        </tr>
        <tr style="background: #f8f9fa;">
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">SonarQube Quality Gate</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '⏭ Skipped' : (currentBuild.result != 'FAILURE' ? 'Passed' : 'Failed')}</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '[skip-scans] flag set' : 'Quality gate evaluated'}</td>
        </tr>
        <tr style="background: #fff;">
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">SCA - OWASP Dependency Check</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '⏭ Skipped' : (currentBuild.result != 'FAILURE' ? 'CVSS < 8.0' : 'CVSS ≥ 8.0 found')}</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '[skip-scans] flag set' : 'See dependency-check-report.html'}</td>
        </tr>
        <tr style="background: #f8f9fa;">
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">Trivy Filesystem Scan</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '⏭ Skipped' : (currentBuild.result != 'FAILURE' ? 'No HIGH/CRITICAL' : 'Vulnerabilities found')}</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '[skip-scans] flag set' : 'See trivy-fs-report.json'}</td>
        </tr>
        <tr style="background: #fff;">
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">Hadolint Dockerfile Scan</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '⏭ Skipped' : 'See report'}</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '[skip-scans] flag set' : 'See hadolint-report.json'}</td>
        </tr>
        <tr style="background: #f8f9fa;">
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">Trivy Image Scan</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '⏭ Skipped' : (currentBuild.result != 'FAILURE' ? 'No HIGH/CRITICAL' : 'Vulnerabilities found')}</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${skipScans ? '[skip-scans] flag set' : 'See trivy-image-report.json'}</td>
        </tr>
        <tr style="background: #fff;">
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">Build & Push to ECR</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${currentBuild.result == 'SUCCESS' ? 'Pushed' : 'Failed'}</td>
          <td style="padding: 8px 12px; border-bottom: 1px solid #dee2e6;">${ecrImage}</td>
        </tr>
      </tbody>
    </table>
  </div>

  <!-- Artifacts -->
  <div style="padding: 16px; border: 1px solid #dee2e6; border-top: none;">
    <h3 style="margin-top: 0;">📎 Artifacts</h3>
    <p>Download from: <a href="${env.BUILD_URL}artifact/">${env.BUILD_URL}artifact/</a></p>
    <ul>
      ${skipScans ? '<li>⏭ Scans skipped — no scan artifacts</li>' : """
      <li><a href="${env.BUILD_URL}artifact/gitleaks-report.json">gitleaks-report.json</a></li>
      <li><a href="${env.BUILD_URL}artifact/reports/dependency-check-report.html">dependency-check-report.html</a></li>
      <li><a href="${env.BUILD_URL}artifact/reports/dependency-check-report.json">dependency-check-report.json</a></li>
      <li><a href="${env.BUILD_URL}artifact/trivy-fs-report.json">trivy-fs-report.json</a></li>
      <li><a href="${env.BUILD_URL}artifact/hadolint-report.json">hadolint-report.json</a></li>
      <li><a href="${env.BUILD_URL}artifact/trivy-image-report.json">trivy-image-report.json</a></li>
      """}
    </ul>
  </div>

  <!-- Footer -->
  <div style="background: #343a40; padding: 10px 16px; border-radius: 0 0 6px 6px;">
    <p style="margin: 0; color: #adb5bd; font-size: 12px;">
      Jenkins CI/CD — ${env.JOB_NAME} — Generated at ${new Date().format("yyyy-MM-dd HH:mm:ss")} UTC
    </p>
  </div>

</body>
</html>
"""
                emailext(
                    subject: "${buildIcon} [${currentBuild.result ?: 'IN PROGRESS'}] ${env.JOB_NAME} — ${microservice} v${semver} — Build #${env.BUILD_NUMBER}",
                    body: emailBody,
                    mimeType: 'text/html',
                    to: env.EMAIL_RECIPIENTS,
                    attachmentsPattern: 'gitleaks-report.json,trivy-fs-report.json,trivy-image-report.json,hadolint-report.json,reports/dependency-check-report.json',
                    allowEmptyArchive: true
                )
            }
        }
    }
}