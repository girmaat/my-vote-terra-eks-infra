#!/bin/bash
set -euo pipefail

CLUSTER_NAME="my-vote-dev"
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
NODE_ROLE_NAME="my-vote-dev-eks-node-role"
EKS_VERSION="1.29"

EXPECTED_POLICIES=(
  "AmazonEKSWorkerNodePolicy"
  "AmazonEKS_CNI_Policy"
  "CloudWatchAgentServerPolicy"
  "AmazonEC2ContainerRegistryReadOnly"
)

BLUE='\033[1;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print() { echo -e "${BLUE}$1${NC}"; }
ok()    { echo -e "${GREEN}[✔] $1${NC}"; }
fail()  { echo -e "${RED}[✘] $1${NC}"; }

print "🔍 Finding Launch Template ID for ASG..."
LT_ID=$(aws autoscaling describe-auto-scaling-groups \
  --region "$AWS_REGION" \
  --query "AutoScalingGroups[?Tags[?Key=='kubernetes.io/cluster/${CLUSTER_NAME}']].LaunchTemplate.LaunchTemplateId" \
  --output text)


if [[ -z "$LT_ID" ]]; then
  fail "No Launch Template found in Auto Scaling Group"
  exit 1
fi
ok "Launch Template ID: $LT_ID"

print "📦 Fetching and decoding user_data..."
USER_DATA=$(aws ec2 describe-launch-template-versions \
  --region "$AWS_REGION" \
  --launch-template-id "$LT_ID" \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
  --output text | base64 -d)

echo "$USER_DATA" > /tmp/bootstrap-debug.sh

if grep -q "bootstrap.sh" /tmp/bootstrap-debug.sh; then
  ok "bootstrap.sh call found in user_data"
else
  fail "bootstrap.sh not found — bootstrap script misconfigured"
  exit 1
fi

CLUSTER=$(grep "bootstrap.sh" /tmp/bootstrap-debug.sh | awk '{print $2}')
ENDPOINT=$(grep -- '--apiserver-endpoint' /tmp/bootstrap-debug.sh | cut -d' ' -f2)
CA_B64=$(grep -- '--b64-cluster-ca' /tmp/bootstrap-debug.sh | cut -d' ' -f2)

echo
print "🧪 Validating extracted values"
echo "Cluster Name:        $CLUSTER"
echo "API Server Endpoint: $ENDPOINT"

print "🔐 Decoding cluster CA cert..."
if echo "$CA_B64" | base64 -d | openssl x509 -noout -text > /dev/null 2>&1; then
  ok "CA cert is valid X.509"
else
  fail "Cluster CA cert is invalid or corrupt"
  exit 1
fi

print "🌐 Checking API server reachability..."
if curl -s --connect-timeout 5 "$ENDPOINT" | grep -q "Unauthorized"; then
  ok "API server reachable (401 Unauthorized is expected)"
else
  fail "API server is not reachable"
fi

print "🔁 Comparing Launch Template AMI to latest..."
AMI_ID=$(aws ec2 describe-launch-template-versions \
  --launch-template-id "$LT_ID" \
  --versions '$Latest' \
  --region "$AWS_REGION" \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.ImageId' \
  --output text)

LATEST_AMI_ID=$(aws ec2 describe-images \
  --owners "602401143452" \
  --filters "Name=name,Values=amazon-eks-node-${EKS_VERSION}-v*" \
  --region "$AWS_REGION" \
  --query 'Images[*].{ID:ImageId,Date:CreationDate}' \
  --output json | jq -r 'sort_by(.Date) | reverse[0].ID')

echo "Launch Template AMI: $AMI_ID"
echo "Latest Amazon EKS AMI ($EKS_VERSION): $LATEST_AMI_ID"

if [[ "$AMI_ID" != "$LATEST_AMI_ID" ]]; then
  fail "Launch Template is using an outdated AMI"
else
  ok "AMI is up to date"
fi

print "🔄 Checking ASG instance lifecycle status..."
aws autoscaling describe-auto-scaling-groups \
  --region "$AWS_REGION" \
  --query "AutoScalingGroups[?contains(AutoScalingGroupName, \`$CLUSTER_NAME\`)].Instances[*].[InstanceId,LifecycleState]" \
  --output table

print "🔐 Checking IMDS token requirement on EC2 instances..."
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=my-vote" \
  --region "$AWS_REGION" \
  --query "Reservations[*].Instances[*].MetadataOptions.HttpTokens" \
  --output text

print "🔐 Checking IAM role policy attachments (Terraform-managed)..."
ATTACHED=$(aws iam list-attached-role-policies \
  --role-name "$NODE_ROLE_NAME" \
  --query "AttachedPolicies[*].PolicyName" \
  --output text)

for POLICY in "${EXPECTED_POLICIES[@]}"; do
  if echo "$ATTACHED" | grep -q "$POLICY"; then
    ok "Policy $POLICY is attached"
  else
    fail "Missing: $POLICY — update modules/eks/iam.tf to avoid drift"
  fi
done

print "✅ Node diagnostics complete. If nodes still do not register, run: kubectl get nodes"
