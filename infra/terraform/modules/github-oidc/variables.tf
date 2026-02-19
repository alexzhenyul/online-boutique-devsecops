variable "github_org" {
  description = "Name of the GitHub organization/user"
  type        = string
}

variable "github_repo" {
  description = "Name of the GitHub repository"
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}