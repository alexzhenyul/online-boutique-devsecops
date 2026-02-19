# Remote State Data Source
# Reads outputs from the Foundation Layer

data "terraform_remote_state" "foundation" {
  backend = "s3"

  config = {
    bucket = var.tf_state_bucket
    key    = "devsecops/${var.environment}/foundation/terraform.tfstate"
    region = var.aws_region
  }
}