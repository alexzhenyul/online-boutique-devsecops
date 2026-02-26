pipeline {
    agent any

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
                        // Updated to match: app/microservices-demo/src/<service>/...
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
                    echo "Detected microservice: ${env.MICROSERVICE}"
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

        stage('Print Result') {
            steps {
                script {
                    if (!env.MICROSERVICE) {
                        echo "No microservice was detected."
                    } else {
                        echo "Would run pipeline for: ${env.MICROSERVICE}"
                    }
                }
            }
        }

    }
}