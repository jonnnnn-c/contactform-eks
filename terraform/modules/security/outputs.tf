output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "cloudtrail_bucket" { value = aws_s3_bucket.trail.id }
