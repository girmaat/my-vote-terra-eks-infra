#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
ENV_DIR="environments/${ENV}"
TF_DIR="${ENV_DIR}/terraform"
PLAN_DIR="${ENV_DIR}/plans"
PLAN_FILE="${PLAN_DIR}/terraform-destroy.tfplan"

GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}[*] Executing destroy for environment: ${ENV}${NC}"
cd "${TF_DIR}"

if [[ ! -f "${PLAN_FILE}" ]]; then
  echo -e "${RED}[!] Destroy plan file '${PLAN_FILE}' not found. Run destroy-plan.sh first.${NC}"
  exit 1
fi

read -p "Are you sure you want to destroy environment '${ENV}'? Type 'yes' to proceed: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo -e "${RED}Aborting.${NC}"
  exit 1
fi

echo -e "${BLUE}[*] Applying destroy plan '${PLAN_FILE}'...${NC}"
terraform apply "${PLAN_FILE}"

echo -e "${BLUE}[*] Running post-destroy validation...${NC}"
../../../scripts/terraform-checks/validate_post_destroy.sh "${ENV}"
