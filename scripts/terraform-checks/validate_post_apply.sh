#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
CLUSTER_NAME="my-vote-${ENV}"
AWS_REGION="us-east-1"

GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

print_section() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
  echo -e "${GREEN}[✔] $1${NC}"
}

print_warning() {
  echo -e "${RED}[✘] $1${NC}"
}

##############################################
# 1. AWS Identity and Region Check
##############################################
print_section "1. AWS Identity and Region Check"

if AWS_PAGER="" aws sts get-caller-identity --output text > /dev/null 2>&1; then
  print_success "AWS identity confirmed"
else
  print_warning "Failed to get AWS identity (credentials issue)"
fi

REG=$(aws configure get region)
if [[ "$REG" == "$AWS_REGION" ]]; then
  print_success "AWS region is correctly set to $AWS_REGION"
else
  print_warning "AWS region mismatch: expected $AWS_REGION but got $REG"
fi

##############################################
# 2. VPC and Subnet Check
##############################################
print_section "2. VPC and Subnet Check"

VPC_COUNT=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=my-vote" --region "$AWS_REGION" --query "Vpcs" | jq 'length')
SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=tag:Project,Values=my-vote" --region "$AWS_REGION" --query "Subnets" | jq 'length')

if [[ "$VPC_COUNT" -gt 0 ]]; then
  print_success "$VPC_COUNT VPC(s) found with tag 'my-vote'"
else
  print_warning "No VPCs found with tag 'my-vote'"
fi

if [[ "$SUBNET_COUNT" -gt 0 ]]; then
  print_success "$SUBNET_COUNT Subnet(s) found with tag 'my-vote'"
else
  print_warning "No subnets found with tag 'my-vote'"
fi

##############################################
# 3. EKS Cluster Status
##############################################
print_section "3. EKS Cluster Status"

if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
  STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.status" --output text)
  ENDPOINT=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.endpoint" --output text)
  print_success "EKS cluster '$CLUSTER_NAME' status: $STATUS"
  echo -e "${BLUE}Cluster endpoint: $ENDPOINT${NC}"
else
  print_warning "EKS cluster '$CLUSTER_NAME' not found"
fi

##############################################
# 4. kubectl connectivity
##############################################
print_section "4. kubectl connectivity"

if command -v kubectl > /dev/null; then
  if kubectl version --client=true > /dev/null 2>&1; then
    print_success "kubectl is installed"
  else
    print_warning "kubectl is not working correctly"
  fi

  if kubectl config current-context > /dev/null 2>&1; then
    print_success "kubectl context is configured"
  else
    print_warning "No current kubectl context set"
  fi

  if kubectl cluster-info > /dev/null 2>&1; then
    print_success "Connected to Kubernetes cluster"
  else
    print_warning "Could not connect to cluster — check kubeconfig and networking"
  fi
else
  print_warning "kubectl is not installed"
fi

##############################################
# 5. EC2 Node Health Check
##############################################
print_section "5. EC2 Node Health Check"

aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=my-vote" \
  --region "$AWS_REGION" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]' \
  --output table

##############################################
# 6. IAM Roles and Instance Profiles
##############################################
print_section "6. IAM Roles and Instance Profiles"

aws iam list-roles \
  --query "Roles[?contains(RoleName, 'my-vote')].RoleName" \
  --output table

aws iam list-instance-profiles \
  --query "InstanceProfiles[?contains(InstanceProfileName, 'my-vote')].InstanceProfileName" \
  --output table

##############################################
# 7. Node Readiness
##############################################
print_section "7. Kubernetes Node Readiness"

if kubectl get nodes > /dev/null 2>&1; then
  TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
  READY_NODES=$(kubectl get nodes --no-headers | grep -c ' Ready')

  if [[ "$TOTAL_NODES" -eq 0 ]]; then
    print_warning "No nodes registered in the cluster"
  elif [[ "$READY_NODES" -eq "$TOTAL_NODES" ]]; then
    print_success "All $READY_NODES node(s) are Ready"
  else
    print_warning "$READY_NODES of $TOTAL_NODES node(s) are Ready"
  fi
else
  print_warning "kubectl get nodes failed — possibly misconfigured cluster or context"
fi

##############################################
# 8. kube-system Pods
##############################################
print_section "8. kube-system Pods"

if kubectl get pods -n kube-system > /dev/null 2>&1; then
  print_success "Listing pods in kube-system namespace:"
  kubectl get pods -n kube-system
else
  print_warning "Failed to retrieve pods from kube-system namespace"
fi
