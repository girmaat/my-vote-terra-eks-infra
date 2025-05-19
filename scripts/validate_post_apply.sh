#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
DIR="environments/${ENV}"
CLUSTER_NAME="my-vote-${ENV}"
AWS_REGION="us-east-1"

GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

print_section() {
  echo -e "\\n${BLUE}=== $1 ===${NC}"
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
aws sts get-caller-identity && print_success "AWS identity confirmed"
aws configure get region | grep -q "$AWS_REGION" \
  && print_success "AWS region is set to $AWS_REGION" \
  || print_warning "AWS region is not $AWS_REGION"

##############################################
# 2. VPC and Subnet Check
##############################################
print_section "2. VPC and Subnet Check"
VPC_COUNT=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=my-vote" --region $AWS_REGION --query "Vpcs" | jq 'length')
SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=tag:Project,Values=my-vote" --region $AWS_REGION --query "Subnets" | jq 'length')

if [[ "$VPC_COUNT" -gt 0 ]]; then
  print_pass "$VPC_COUNT VPC(s) found with tag 'my-vote'"
else
  print_fail "No VPCs found with tag 'my-vote'"
fi

if [[ "$SUBNET_COUNT" -gt 0 ]]; then
  print_pass "$SUBNET_COUNT Subnet(s) found with tag 'my-vote'"
else
  print_fail "No subnets found with tag 'my-vote'"
fi


##############################################
# 3. EKS Cluster Status
##############################################
print_section "3. EKS Cluster Status"
aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION | jq '.cluster.status' || print_warning "Cluster not found"

##############################################
# 4. kubectl connectivity
##############################################
print_section "4. kubectl connectivity"
kubectl version --short || print_warning "kubectl not configured"
kubectl config current-context || print_warning "No current context"
kubectl cluster-info || print_warning "Could not connect to cluster"

##############################################
# 5. EC2 Node Health Check
##############################################
print_section "5. EC2 Node Health Check"
aws ec2 describe-instances --filters "Name=tag:Project,Values=my-vote" --region $AWS_REGION \
  --query 'Reservations[*].Instances[*].State.Name' --output table

##############################################
# 6. IAM Roles and Instance Profiles
##############################################
print_section "6. IAM Roles and Instance Profiles"
aws iam list-roles --query "Roles[?contains(RoleName, 'my-vote')].RoleName" --output table
aws iam list-instance-profiles --query "InstanceProfiles[?contains(InstanceProfileName, 'my-vote')].InstanceProfileName" --output table

##############################################
# 7. Node Registration Status
##############################################
print_section "7. kubectl node status (should be empty before aws-auth patch)"
kubectl get nodes || print_warning "Nodes not yet registered — expected before aws-auth patch"
