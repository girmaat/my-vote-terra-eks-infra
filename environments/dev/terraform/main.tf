module "vpc" {
  source = "../../../modules/vpc"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  aws_region           = var.aws_region
}
module "eks" {
  source             = "../../../modules/eks"
  cluster_name       = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  aws_region         = var.aws_region
  project            = var.project
  environment        = var.environment
}

module "eks_nodes" {
  source                = "../../../modules/eks_nodes"
  cluster_name          = module.eks.cluster_name
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  instance_profile_name = module.eks_nodes.instance_profile_name
  node_role_name        = module.eks.worker_role_name
  cluster_endpoint      = module.eks.cluster_endpoint
  cluster_ca            = module.eks.cluster_ca
}


