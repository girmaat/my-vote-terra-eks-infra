variable "name" {
  description = "Name of the IAM role"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider from EKS cluster"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without https://"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the service account"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name"
  type        = string
}

variable "policy_arns" {
  description = "List of IAM policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the IAM role"
  type        = map(string)
  default     = {}
}
