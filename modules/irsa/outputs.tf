output "role_arn" {
  description = "IAM Role ARN created for IRSA"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "IAM Role name"
  value       = aws_iam_role.this.name
}
