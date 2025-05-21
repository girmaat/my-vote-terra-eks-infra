resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = indent(2, yamlencode([
      {
        rolearn  = aws_iam_role.eks_node.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes"
        ]
      }
    ]))

    # Optional: Add mapUsers if you want to grant admin access via IAM users
    # mapUsers = indent(2, yamlencode([
    #   {
    #     userarn  = "arn:aws:iam::123456789012:user/your-admin-user"
    #     username = "admin"
    #     groups   = ["system:masters"]
    #   }
    # ]))
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_autoscaling_group.eks_nodes
  ]
}
