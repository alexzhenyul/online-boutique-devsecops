# VPC Module Variables

variable "cluster_name" {
  description = "Name of the EKS cluster (used for resource naming and tagging)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Recommended: /16 for large deployments"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to use. Minimum 2, recommended 3 for production"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 6
    error_message = "AZ count must be between 2 and 6."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    Use a single NAT Gateway instead of one per AZ.
    - true: Cost-effective for dev/test (single point of failure)
    - false: High availability for production (one NAT GW per AZ)
  EOT
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = <<-EOT
    Enable VPC endpoints for AWS services (ECR, S3, EC2, STS, Logs).
    - Reduces NAT Gateway data transfer costs
    - Required for fully private EKS clusters
    - Increases cost (interface endpoints have hourly charges)
  EOT
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for network traffic monitoring"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retention period for VPC Flow Logs in CloudWatch (days)"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}