# VPC Module Outputs

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (use for EKS nodes)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value       = aws_subnet.private[*].cidr_block
}

output "nat_gateway_ips" {
  description = "List of NAT Gateway public IPs"
  value       = aws_eip.nat[*].public_ip
}

output "availability_zones" {
  description = "List of Availability Zones used"
  value       = local.azs
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "vpc_endpoints" {
  description = "Map of VPC endpoint IDs"
  value = var.enable_vpc_endpoints ? {
    s3      = aws_vpc_endpoint.s3[0].id
    ecr_api = aws_vpc_endpoint.ecr_api[0].id
    ecr_dkr = aws_vpc_endpoint.ecr_dkr[0].id
    ec2     = aws_vpc_endpoint.ec2[0].id
    sts     = aws_vpc_endpoint.sts[0].id
    logs    = aws_vpc_endpoint.logs[0].id
  } : {}
}

output "vpc_summary" {
  description = "Summary of VPC configuration"
  value = {
    vpc_id          = aws_vpc.main.id
    cidr            = aws_vpc.main.cidr_block
    azs             = local.azs
    public_subnets  = length(aws_subnet.public)
    private_subnets = length(aws_subnet.private)
    nat_gateways    = var.single_nat_gateway ? 1 : var.az_count
    vpc_endpoints   = var.enable_vpc_endpoints
    flow_logs       = var.enable_flow_logs
  }
}