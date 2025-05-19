#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
DIR="environments/${ENV}"
PLAN_FILE="terraform.tfplan"

GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}[*] Applying Terraform for environment: ${ENV}${NC}"
cd "${DIR}"

if [[ ! -f "${PLAN_FILE}" ]]; then
  echo -e "${RED}[!] Plan file '${PLAN_FILE}' not found. Please run plan.sh first.${NC}"
  exit 1
fi

echo -e "${BLUE}[*] Applying saved plan '${PLAN_FILE}'...${NC}"
terraform apply "${PLAN_FILE}"
