#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
CLUSTER_NAME="my-vote-${ENV}"
AWS_REGION="us-east-1"

BLUE='\033[1;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_section() {
  echo -e "\\n${BLUE}=== $1 ===${NC}"
}

print_pass() {
  echo -e "${GREEN}[✔] $1${NC}"
}

print_fail() {
  echo -e "${RED}[✘] $1${NC}"
}

##########################
# 1. VPC Check
##########################
print_section "VPC Check"
VPC_COUNT=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=my-vote" --region $AWS_REGION --query "Vpcs" | jq 'length')
if [[ "$VPC_COUNT" -eq 0 ]]; then
  print_pass "No VPCs found with 'my-vote' tag"
else
  print_fail "$VPC_COUNT VPC(s) still exist with 'my-vote' tag"
fi

##########################
# 2. EKS Cluster
##########################
print_section "EKS Cluster Check"
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
  print_fail "EKS cluster '$CLUSTER_NAME' still exists"
else
  print_pass "EKS cluster '$CLUSTER_NAME' successfully deleted"
fi

##########################
# 3. EC2 Instances
##########################
print_section "EC2 Node Check"
EC2_COUNT=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=my-vote" --region $AWS_REGION \
  --query "Reservations[*].Instances[*].InstanceId" --output text | wc -w)

if [[ "$EC2_COUNT" -eq 0 ]]; then
  print_pass "No EC2 instances found for EKS nodes"
else
  print_fail "$EC2_COUNT EC2 instance(s) still running"
fi

##########################
# 4. IAM Roles
##########################
print_section "IAM Role Check"
IAM_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'my-vote')].RoleName" --output text)
if [[ -z "$IAM_ROLES" ]]; then
  print_pass "No IAM roles with 'my-vote' found"
else
  print_fail "IAM roles still exist: $IAM_ROLES"
fi

##########################
# 5. Instance Profiles
##########################
print_section "IAM Instance Profiles"
PROFILES=$(aws iam list-instance-profiles --query "InstanceProfiles[?contains(InstanceProfileName, 'my-vote')].InstanceProfileName" --output text)
if [[ -z "$PROFILES" ]]; then
  print_pass "No IAM instance profiles with 'my-vote'"
else
  print_fail "Instance profiles still exist: $PROFILES"
fi
