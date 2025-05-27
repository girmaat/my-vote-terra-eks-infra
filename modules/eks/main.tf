resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.29"

  vpc_config {
    subnet_ids = var.private_subnet_ids
  }

  tags = {
    Name        = var.cluster_name
    Project     = var.project
    Environment = var.environment
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}
