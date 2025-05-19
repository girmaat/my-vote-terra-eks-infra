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

output "asg_name" {
  value = aws_autoscaling_group.eks_nodes.name
}
