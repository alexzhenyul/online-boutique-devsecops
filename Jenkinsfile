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