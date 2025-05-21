#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
DIR="environments/${ENV}/terraform"
PLAN_FILE="terraform.tfplan"

GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}[*] Planning Terraform for environment: ${ENV}${NC}"
cd "${DIR}"

echo -e "${BLUE}[*] Formatting Terraform files...${NC}"
terraform fmt -recursive

echo -e "${BLUE}[*] Validating Terraform configuration...${NC}"
terraform validate && echo -e "${GREEN}[✔] Validation passed${NC}"

echo -e "${BLUE}[*] Generating plan and saving to '${PLAN_FILE}'...${NC}"
terraform plan -var-file="terraform.tfvars" -out="${PLAN_FILE}"
echo -e "${GREEN}[✔] Plan saved successfully to ${PLAN_FILE}${NC}"
