#!/bin/bash
set -euo pipefail

BLUE="\033[1;34m"
RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

print_section() {
  echo -e "\n${BLUE}== $1 ==${NC}"
}

print_ok() {
  echo -e "${GREEN}[✔] $1${NC}"
}

print_fail() {
  echo -e "${RED}[✘] $1${NC}"
}

# 1. Node status
print_section "Node Status"
kubectl get nodes || print_fail "Failed to get nodes"

# 2. CNI pod status
print_section "aws-node (CNI) Pod Status"
kubectl get pods -n kube-system -l k8s-app=aws-node -o wide || print_fail "Failed to get aws-node pods"

# 3. coredns scheduling
print_section "coredns Pod Scheduling"
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide || print_fail "Failed to get CoreDNS pods"

# 4. Subnet tag check
print_section "Subnet Tag Check"
aws ec2 describe-subnets --filters "Name=tag:Project,Values=my-vote"   --query "Subnets[*].{ID:SubnetId,Tags:Tags}" --output table || print_fail "Failed to fetch subnet tags"

# 5. Node IAM policy check
print_section "IAM Role Policies for Node Role"
NODE_ROLE_NAME=$(aws iam list-roles --query "Roles[?contains(RoleName, 'my-vote-dev-eks-node-role')].RoleName" --output text)
aws iam list-attached-role-policies --role-name "$NODE_ROLE_NAME" --query "AttachedPolicies[*].PolicyName" --output table || print_fail "Could not list attached policies"

# 6. aws-node CNI log check for first instance
print_section "aws-node Log Summary (first pod)"
FIRST_POD=$(kubectl get pods -n kube-system -l k8s-app=aws-node -o jsonpath="{.items[0].metadata.name}")
kubectl logs -n kube-system "$FIRST_POD" -c aws-node --tail=30 || print_fail "Failed to get logs from aws-node"

echo -e "\n${BLUE}✅ Cluster readiness + CNI log check complete. Use this output to finalize network health.${NC}"
