#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
DIR="environments/${ENV}/terraform"
PLAN_FILE="terraform.tfplan"
CLUSTER_NAME="my-vote-${ENV}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color
echo -e "${BLUE}[*] Applying Terraform for environment: ${ENV}${NC}"
cd "${DIR}"

echo -e "${BLUE}[*] Looking for plan file at: ${PLAN_FILE}${NC}"
if [[ ! -f "${PLAN_FILE}" ]]; then
  echo -e "${RED}[!] Plan file '${PLAN_FILE}' not found in ${DIR}. Please run plan.sh first.${NC}"
  exit 1
fi

echo -e "${BLUE}[*] Applying saved plan '${PLAN_FILE}'...${NC}"
terraform apply -auto-approve "${PLAN_FILE}"

echo -e "${BLUE}[*] Running post-apply validation...${NC}"
"${ROOT_DIR}/scripts/terraform-checks/validate_post_apply.sh" "${ENV}" || {
  echo -e "${RED}[!] Post-apply validation failed. Investigate aws-auth and node readiness.${NC}"
}

echo -e "${BLUE}[*] Updating kubeconfig for kubectl access...${NC}"
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME"

# Confirm kubectl access
if ! kubectl get nodes > /dev/null 2>&1; then
  echo -e "${RED}[✘] kubectl could not connect to the cluster. Check kubeconfig and IAM permissions.${NC}"
  exit 1
fi

echo -e "${BLUE}[*] Waiting for nodes to become Ready...${NC}"

TIMEOUT=300
SLEEP_INTERVAL=10
ELAPSED=0
READY_NODES=0

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')
  if [[ "$READY_NODES" -gt 0 ]]; then
    echo -e "${GREEN}[✔] $READY_NODES node(s) are Ready${NC}"
    break
  else
    echo -e "${BLUE}[i] No Ready nodes yet — waiting (${ELAPSED}s elapsed)...${NC}"
    sleep $SLEEP_INTERVAL
    ELAPSED=$((ELAPSED + SLEEP_INTERVAL))
  fi
done

if [[ "$READY_NODES" -eq 0 ]]; then
  echo -e "${RED}[✘] Timeout reached. No nodes became Ready. Check aws-auth, IAM role, and networking.${NC}"
  exit 1
fi

echo -e "${GREEN}[✔] Terraform apply and EKS node readiness complete for '${CLUSTER_NAME}'${NC}"
