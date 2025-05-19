
#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
AWS_REGION="us-east-1"
CLUSTER_NAME="my-vote-${ENV}"
REPORT_DIR="reports"
JSON_LOG="${REPORT_DIR}/pre_apply_check.json"
HTML_LOG="${REPORT_DIR}/pre_apply_check.html"

mkdir -p "${REPORT_DIR}"

GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

RESULTS=()

print_section() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
  RESULTS+=("{\"section\": \"$1\", \"results\": []}")
}

record_result() {
  local message=$1
  local success=$2
  if [ "$success" = true ]; then
    echo -e "${GREEN}[✔] $message${NC}"
    RESULTS[-1]=$(echo "${RESULTS[-1]}" | jq --arg msg "$message" '.results += [{"status":"pass","message":$msg}]')
  else
    echo -e "${RED}[✘] $message${NC}"
    RESULTS[-1]=$(echo "${RESULTS[-1]}" | jq --arg msg "$message" '.results += [{"status":"fail","message":$msg}]')
  fi
}

print_section "1. Confirm AWS Identity"
if aws sts get-caller-identity > /dev/null 2>&1; then
  record_result "AWS identity confirmed" true
else
  record_result "Failed to get AWS identity" false
fi

print_section "2. Confirm AWS Region"
REG=$(aws configure get region)
if [[ "$REG" == "$AWS_REGION" ]]; then
  record_result "Region is correctly set to $AWS_REGION" true
else
  record_result "Region mismatch: expected $AWS_REGION, got $REG" false
fi

print_section "3. Check for Existing EKS Cluster"
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
  record_result "EKS cluster '$CLUSTER_NAME' already exists" false
else
  record_result "No existing EKS cluster with name '$CLUSTER_NAME'" true
fi

print_section "4. Check for Existing IAM Roles"
EXISTING_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, 'my-vote')].RoleName" --output text)
if [[ -z "$EXISTING_ROLES" ]]; then
  record_result "No conflicting IAM roles found" true
else
  record_result "Conflicting IAM roles found: $EXISTING_ROLES" false
fi

print_section "5. Check for Existing Instance Profiles"
EXISTING_PROFILES=$(aws iam list-instance-profiles --query "InstanceProfiles[?contains(InstanceProfileName, 'my-vote')].InstanceProfileName" --output text)
if [[ -z "$EXISTING_PROFILES" ]]; then
  record_result "No conflicting instance profiles found" true
else
  record_result "Conflicting instance profiles found: $EXISTING_PROFILES" false
fi

# Save JSON
echo "${RESULTS[@]}" | jq -s '.' > "${JSON_LOG}"

# Generate HTML
{
echo "<html><body><h2>Terraform Pre-Apply Checklist Report</h2>"
jq -r '.[] | "<h3>\(.section)</h3><ul>" + (.results[] | "<li style=color:\(if .status=="pass" then "green" else "red" end)>[\(.status|ascii_upcase)] \(.message)</li>") + "</ul>"' "${JSON_LOG}"
echo "</body></html>"
} > "${HTML_LOG}"

echo -e "\n${BLUE}✅ Report written to ${HTML_LOG}${NC}"

# Check for any failed checks in JSON
if jq -e '[.[][] | select(.status == "fail")] | length > 0' "${JSON_LOG}" > /dev/null; then
  echo -e "${RED}[✘] One or more pre-apply checks FAILED. Terraform apply is not safe.${NC}"
  exit 1
else
  echo -e "${GREEN}[✔] All pre-apply checks passed. Safe to proceed with Terraform apply.${NC}"
fi

# Attempt to open (if terminal supports it)
if command -v xdg-open &> /dev/null; then
  xdg-open "${HTML_LOG}" > /dev/null 2>&1 &
elif command -v open &> /dev/null; then
  open "${HTML_LOG}" > /dev/null 2>&1 &
else
  echo -e "${BLUE}[i] To view the report, open: ${HTML_LOG}${NC}"
fi
