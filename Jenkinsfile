pipeline {
    agent any

    stages {

        stage('Checkout') {
            steps {
                echo "Checking out code..."
                checkout scm
            }
        }

        stage('Detect Changed Services') {
            steps {
                script {
                    // Get changed files in the last commit
                    def changedFiles = sh(
                        script: "git diff --name-only HEAD~1 || true",
                        returnStdout: true
                    ).trim()

                    echo "Changed files:\n${changedFiles}"

                    def services = []

                    changedFiles.split("\n").each { file ->
                        // Only consider files under app/microservices-demo/src/
                        if (file.startsWith("app/microservices-demo/src/")) {
                            // service folder is the first folder under src
                            def svc = file.tokenize('/')[4] // adjust for your folder depth
                            services.add(svc)
                        }
                    }

                    // Remove duplicates
                    SERVICES = services.unique()

                    if (SERVICES.isEmpty()) {
                        echo "No services changed in this commit."
                    } else {
                        echo "Changed services: ${SERVICES}"
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Service detection completed."
        }
    }
}