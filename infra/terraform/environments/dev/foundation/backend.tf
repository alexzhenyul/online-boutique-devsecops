terraform {
  backend "s3" {
    bucket       = "online-boutique-devsecops"                  # Configured via backend-config
    key          = "devsecops/dev/foundation/terraform.tfstate" # Configured via backend-config
    region       = "ap-southeast-4"                             # Configured via backend-config
    encrypt      = true
    use_lockfile = true
  }
}