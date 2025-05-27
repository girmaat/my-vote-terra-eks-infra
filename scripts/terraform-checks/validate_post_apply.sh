#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
CLUSTER_NAME="my-vote-${ENV}"
AWS_REGION="us-east-1"
FIX_MODE="false"

if [[ "${2:-}" == "--fix" ]]; then
  FIX_MODE="true"
fi

GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

print_section() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
  echo -e "${GREEN}[\u2714] $1${NC}"
}

print_warning() {
  echo -e "${RED}[\u2718] $1${NC}"
}

fix_ec2_nodes() {
  echo -e "${BLUE}[*] Attempting to fix missing EC2 nodes by tainting the ASG...${NC}"
  pushd "environments/${ENV}/terraform" > /dev/null
  terraform init -input=false
  terraform taint module.eks.aws_autoscaling_group.eks_nodes || true
  terraform apply -auto-approve
  popd > /dev/null
  print_success "Terraform re-applied to re-trigger EC2 node provisioning"

  echo -e "${BLUE}[*] Waiting for EC2 to become Ready (240s)...${NC}"
  sleep 240

  EC2_INFO_POSTFIX=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=my-vote" \
    --region "$AWS_REGION" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value | [0],PrivateIpAddress]' \
    --output table)

  if [[ -z "$EC2_INFO_POSTFIX" || "$EC2_INFO_POSTFIX" == "None" ]]; then
    print_warning "❌ EC2 nodes still not present after remediation. Manual intervention needed."
  else
    print_success "✅ EC2 worker nodes detected after fix:"
    echo "$EC2_INFO_POSTFIX"
  fi
}

check_and_fix_aws_auth() {
  EXPECTED_ROLE="my-vote-dev-eks-node-role"

  # Check for node IAM role presence
  if ! kubectl get configmap aws-auth -n kube-system -o yaml | grep -q "$EXPECTED_ROLE"; then
    print_warning "❌ Node IAM role '$EXPECTED_ROLE' is missing from aws-auth ConfigMap"
  else
    print_success "✅ Node IAM role '$EXPECTED_ROLE' found in aws-auth"
  fi

  # Check formatting
  if ! kubectl get configmap aws-auth -n kube-system -o yaml | grep -q 'mapRoles: |'; then
    print_warning "❌ aws-auth ConfigMap is malformed (not using proper YAML block format)"
    if [[ "$FIX_MODE" == "true" ]]; then
      echo -e "${BLUE}[*] Reapplying aws-auth ConfigMap using Terraform...${NC}"
      pushd "environments/${ENV}/terraform" > /dev/null
      terraform init -input=false
      terraform apply -target=module.eks.kubernetes_config_map.aws_auth -auto-approve || true
      popd > /dev/null
      print_success "aws-auth ConfigMap reapplied"

      echo -e "${BLUE}[*] Waiting for nodes to join after fix (2 min max)...${NC}"
      for i in {1..8}; do
        NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        if [[ "$NODE_COUNT" -gt 0 ]]; then
          print_success "✅ $NODE_COUNT Kubernetes node(s) joined the cluster"
          kubectl get nodes
          return
        fi
        echo -e "${BLUE}... still waiting, retry ${i}/8 (sleep 15s)${NC}"
        sleep 15
      done

      print_warning "❌ Nodes did not join the cluster after aws-auth fix. Check EC2 bootstrap logs."
    else
      print_warning "Run with --fix to auto-correct malformed aws-auth"
    fi
  fi
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

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" > /dev/null

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

EC2_INFO=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=my-vote" \
  --region "$AWS_REGION" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value | [0],PrivateIpAddress]' \
  --output table)

if [[ -z "$EC2_INFO" || "$EC2_INFO" == "None" ]]; then
  print_warning "\u274C No EC2 instances found for worker nodes — Auto Scaling Group may not be launching"
  if [[ "$FIX_MODE" == "true" ]]; then
    fix_ec2_nodes
  else
    print_warning "🔧 Run with '--fix' to attempt automatic remediation."
  fi
else
  print_success "EC2 worker instances detected:"
  echo "$EC2_INFO"
  check_and_fix_aws_auth
fi

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
# 7. Kubernetes Node Readiness
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
