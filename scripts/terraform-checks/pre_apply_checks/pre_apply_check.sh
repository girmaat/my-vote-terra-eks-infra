#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
AWS_REGION="us-east-1"
CLUSTER_NAME="my-vote-${ENV}"
SCRIPT_DIR="$(dirname "$0")"
REPORT_DIR="${SCRIPT_DIR}/reports"
JSON_LOG="${REPORT_DIR}/pre_apply_check.json"
HTML_LOG="${REPORT_DIR}/pre_apply_check.html"
RESULTS_FILE=$(mktemp)

mkdir -p "${REPORT_DIR}"
echo "[]" > "$RESULTS_FILE"

GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

print_section() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

record_result() {
  local section="$1"
  local message="$2"
  local status="$3"

  jq \
    --arg section "$section" \
    --arg message "$message" \
    --arg status "$status" \
    '. += [{"section": $section, "status": $status, "message": $message}]' \
    "$RESULTS_FILE" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"

  if [[ "$status" == "pass" ]]; then
    echo -e "${GREEN}[✔] $message${NC}"
  else
    echo -e "${RED}[✘] $message${NC}"
  fi
}

#######################################
# 1. AWS Identity and Region Check
#######################################
print_section "1. Confirm AWS Identity"
if aws sts get-caller-identity > /dev/null 2>&1; then
  record_result "1. Confirm AWS Identity" "AWS identity confirmed" "pass"
else
  record_result "1. Confirm AWS Identity" "Failed to get AWS identity" "fail"
fi

print_section "2. Confirm AWS Region"
REG=$(aws configure get region)
if [[ "$REG" == "$AWS_REGION" ]]; then
  record_result "2. Confirm AWS Region" "Region is correctly set to $AWS_REGION" "pass"
else
  record_result "2. Confirm AWS Region" "Region mismatch: expected $AWS_REGION, got $REG" "fail"
fi

#######################################
# 2. Resource Pre-Existence Checks
#######################################
print_section "3. Check for Existing EKS Cluster"
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
  record_result "3. Check for Existing EKS Cluster" "EKS cluster '$CLUSTER_NAME' already exists" "fail"
else
  record_result "3. Check for Existing EKS Cluster" "No existing EKS cluster with name '$CLUSTER_NAME'" "pass"
fi

print_section "4. Check for Existing IAM Roles"
EXISTING_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'my-vote')].RoleName" --output text)
if [[ -z "$EXISTING_ROLES" ]]; then
  record_result "4. Check for Existing IAM Roles" "No conflicting IAM roles found" "pass"
else
  record_result "4. Check for Existing IAM Roles" "Conflicting IAM roles found: $EXISTING_ROLES" "fail"
fi

print_section "5. Check for Existing Instance Profiles"
EXISTING_PROFILES=$(aws iam list-instance-profiles --query "InstanceProfiles[?contains(InstanceProfileName, 'my-vote')].InstanceProfileName" --output text)
if [[ -z "$EXISTING_PROFILES" ]]; then
  record_result "5. Check for Existing Instance Profiles" "No conflicting instance profiles found" "pass"
else
  record_result "5. Check for Existing Instance Profiles" "Conflicting instance profiles found: $EXISTING_PROFILES" "fail"
fi

#######################################
# 6. kubectl Configuration Check
#######################################
print_section "6. kubectl Configuration (if applicable)"

if command -v kubectl > /dev/null; then
  if kubectl cluster-info > /dev/null 2>&1; then
    record_result "6. kubectl Configuration" "kubectl is configured and can reach a cluster" "pass"
  else
    record_result "6. kubectl Configuration" "kubectl is installed but cluster not reachable (likely not yet created)" "fail"
  fi
else
  record_result "6. kubectl Configuration" "kubectl is not installed" "fail"
fi

#######################################
# Save Results and Output Report
#######################################
cp "$RESULTS_FILE" "$JSON_LOG"

# Generate HTML Report
{
echo "<html><body><h2>Terraform Pre-Apply Checklist Report</h2>"
jq -r '[.[]] | group_by(.section)[] | "<h3>\(.[0].section)</h3><ul>" + (map("<li style=color:\(if .status == "pass" then "green" else "red" end)>[\(.status|ascii_upcase)] \(.message)</li>") | join("")) + "</ul>"' "$JSON_LOG"
echo "</body></html>"
} > "$HTML_LOG"

echo -e "\n${BLUE}✅ Report written to ${HTML_LOG}${NC}"

# Final result: fail if any check failed
if jq -e '[.[] | select(.status == "fail")] | length > 0' "$JSON_LOG" > /dev/null; then
  echo -e "${RED}[✘] One or more pre-apply checks FAILED. Terraform apply is not safe.${NC}"
  exit 1
else
  echo -e "${GREEN}[✔] All pre-apply checks passed. Safe to proceed with Terraform apply.${NC}"
fi

# Attempt to open (if supported)
if command -v xdg-open &> /dev/null; then
  xdg-open "$HTML_LOG" > /dev/null 2>&1 &
elif command -v open &> /dev/null; then
  open "$HTML_LOG" > /dev/null 2>&1 &
else
  echo -e "${BLUE}[i] To view the report, open: $HTML_LOG${NC}"
fi
