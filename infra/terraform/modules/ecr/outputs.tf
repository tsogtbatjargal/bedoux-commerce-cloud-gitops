output "repository_urls" {
  value = {
    for name, repository in aws_ecr_repository.this : name => repository.repository_url
  }
}

output "repository_arns" {
  value = [for repository in aws_ecr_repository.this : repository.arn]
}
