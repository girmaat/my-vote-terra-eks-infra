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



resource "aws_security_group" "eks_nodes" {
  name   = "${var.project}-${var.environment}-eks-nodes"
  vpc_id = var.vpc_id

  ingress {
    description = "Allow node-to-node"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Allow control plane to kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Or restrict to AWS EKS IP ranges
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-nodes"
  }
}

resource "aws_launch_template" "eks_nodes" {
  name_prefix   = "${var.cluster_name}-lt-"
  image_id      = data.aws_ami.eks_ami.id
  instance_type = "t3.medium"

  iam_instance_profile {
    name = aws_iam_instance_profile.eks_node.name
  }

  user_data = base64encode(
    templatefile("${path.module}/bootstrap.tpl", {
      cluster_name     = aws_eks_cluster.main.name
      cluster_endpoint = aws_eks_cluster.main.endpoint
      cluster_ca       = aws_eks_cluster.main.certificate_authority[0].data
    })
  )

  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "optional" # "required" also works but your bootstrap must handle IMDSv2 tokens
  }
}


resource "aws_iam_instance_profile" "eks_node" {
  name = "${var.cluster_name}-node-profile"
  role = aws_iam_role.eks_node.name
}

data "aws_ami" "eks_ami" {
  owners      = ["602401143452"] # Amazon EKS optimized AMIs
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-1.29-v*"]
  }
}

resource "aws_autoscaling_group" "eks_nodes" {
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = var.private_subnet_ids
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }
}
