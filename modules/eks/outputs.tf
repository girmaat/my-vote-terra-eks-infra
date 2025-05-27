output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_ca" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

output "worker_role_arn" {
  value = aws_iam_role.eks_node.arn
}



output "aws_auth_config" {
  description = "Final aws-auth mapRoles ConfigMap rendered"
  value       = kubernetes_config_map.aws_auth.data
}


output "worker_role_name" {
  description = "IAM role name used by EKS worker nodes"
  value       = aws_iam_role.eks_node.name
}
