# General
aws_region  = "ap-southeast-4"
environment = "dev"

# State Configuration (Must match Foundation)
tf_state_bucket = "online-boutique-devsecops"

# GitOps
enable_aws_managed_gitops = false
enable_helm_argocd        = true
gitops_repo_url           = "https://github.com/alexzhenyul/online-boutique-devsecops.git"

# Advanced Controllers
enable_ack = false
enable_kro = false