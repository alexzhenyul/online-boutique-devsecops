pipeline {
    agent any

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Detect Changed Services') {
            steps {
                script {
                    // Get changed files from the last commit
                    def changedFiles = sh(
                        script: "git diff --name-only HEAD~1 || true",
                        returnStdout: true
                    ).trim()

                    echo "Changed files:\n${changedFiles}"

                    def services = []

                    changedFiles.split("\n").each { file ->
                        // Only consider files under app/microservices-demo/src/
                        if (file.startsWith("app/microservices-demo/src/")) {
                            // service name is the folder after src/
                            def svc = file.tokenize('/')[4] // 0=app,1=microservices-demo,2=src,3=service-type?,4=service-name?
                            services.add(svc)
                        }
                    }

                    // Remove duplicates
                    SERVICES = services.unique()

                    echo "Detected services: ${SERVICES}"
                }
            }
        }
    }
}