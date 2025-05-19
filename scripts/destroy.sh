#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
DIR="environments/${ENV}"
PLAN_FILE="terraform-destroy.tfplan"

GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}[*] Executing destroy for environment: ${ENV}${NC}"
cd "${DIR}"

if [[ ! -f "${PLAN_FILE}" ]]; then
  echo -e "${RED}[!] Destroy plan file '${PLAN_FILE}' not found. Run destroy-plan.sh first.${NC}"
  exit 1
fi

echo -e "${BLUE}[*] Applying destroy plan '${PLAN_FILE}'...${NC}"
terraform apply "${PLAN_FILE}"
