
stage('Detect Changed Services') {
    steps {
        script {

            // Get list of changed files in the last commit
            def changedFiles = sh(
                script: "git diff --name-only HEAD~1 || true",
                returnStdout: true
            ).trim()

            echo "Changed files:\n${changedFiles}"

            def services = []

            changedFiles.split("\n").each { file ->
                // Only consider files under app/microservices-demo/
                if (file.startsWith("app/microservices-demo/")) {
                    def svc = file.tokenize('/')[2]  // 2 = service folder
                    services.add(svc)
                }
            }

            // Remove duplicates
            SERVICES = services.unique()

            echo "Detected services: ${SERVICES}"
        }
    }
}