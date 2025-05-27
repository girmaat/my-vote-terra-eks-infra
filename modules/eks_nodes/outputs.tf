output "instance_profile_name" {
  description = "Name of the IAM instance profile used by worker nodes"
  value       = aws_iam_instance_profile.eks_node.name
}
