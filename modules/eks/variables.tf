variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EKS is deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for node placement"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
