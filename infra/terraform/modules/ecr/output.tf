output "repository_urls" {
  description = "Map of microservice name to ECR repository URL"
  value = {
    for name, repo in aws_ecr_repository.this :
    name => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of microservice name to ECR repository ARN"
  value = {
    for name, repo in aws_ecr_repository.this :
    name => repo.arn
  }
}

output "registry_id" {
  description = "ECR registry ID (AWS account ID)"
  value       = values(aws_ecr_repository.this)[0].registry_id
}

# Kept for backwards compatibility - returns all repo names as a list
output "repository_names" {
  description = "List of all ECR repository names"
  value       = keys(aws_ecr_repository.this)
}