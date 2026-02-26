resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)   

  name                 = each.value         
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Microservice = each.value               
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = toset(var.repository_names) 
  repository = aws_ecr_repository.this[each.value].name  

  policy = var.lifecycle_policy_json != "" ? var.lifecycle_policy_json : <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 30 images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["v"],
                "countType": "imageCountMoreThan",
                "countNumber": 30
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 2,
            "description": "Expire untagged images older than 14 days",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 14
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}