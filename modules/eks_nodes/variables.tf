variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC for worker nodes"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for autoscaling group"
  type        = list(string)
}


variable "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  type        = string
}

variable "cluster_ca" {
  description = "EKS cluster certificate authority"
  type        = string
}

variable "node_role_name" {
  description = "IAM role name for EKS worker nodes"
  type        = string
}
