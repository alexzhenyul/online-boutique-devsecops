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
                def changedFiles = sh(
                    script: "git diff --name-only HEAD~1 || true",
                    returnStdout: true
                ).trim()

                echo "Changed files:\n${changedFiles}"

                def services = []

                changedFiles.split("\n").each { file ->
                    if (file.startsWith("app/microservices-demo/src/")) {
                        // Service folder is index 3
                        def svc = file.tokenize('/')[3]
                        services.add(svc)
                    }
                }

                SERVICES = services.unique()

                if (SERVICES.isEmpty()) {
                    echo "No services changed ingit this commit."
                } else {
                    echo "Changed services: ${SERVICES}"
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
}