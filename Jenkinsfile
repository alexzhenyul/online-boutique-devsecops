pipeline {
    agent any

    environment {
        // AWS & ECR
        AWS_REGION      = 'ap-southeast-4'
        ECR_REGISTRY    = '253343486660.dkr.ecr.ap-southeast-4.amazonaws.com'
        ECR_REPO_PREFIX = 'online-boutique'
        
        // OWASP
        DC_DATA_DIR     = '/var/lib/jenkins/dependency-check-data'
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
                    sh """
                        git config user.email "jenkins@ci"
                        git config user.name  "Jenkins"
                        git tag "${env.MICROSERVICE}/${env.SEMVER}"
                        git push origin "${env.MICROSERVICE}/${env.SEMVER}"
                    """
                    echo "Git tag created: ${env.MICROSERVICE}/${env.SEMVER}"
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
}