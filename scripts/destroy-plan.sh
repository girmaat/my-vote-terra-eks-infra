#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
DIR="environments/${ENV}"
PLAN_FILE="terraform-destroy.tfplan"

GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}[*] Generating destroy plan for environment: ${ENV}${NC}"
cd "${DIR}"

echo -e "${BLUE}[*] Formatting Terraform files...${NC}"
terraform fmt -recursive

echo -e "${BLUE}[*] Validating Terraform configuration...${NC}"
terraform validate && echo -e "${GREEN}[✔] Validation passed${NC}"

echo -e "${BLUE}[*] Saving destroy plan to '${PLAN_FILE}'...${NC}"
terraform plan -destroy -var-file="terraform.tfvars" -out="${PLAN_FILE}"
echo -e "${GREEN}[✔] Destroy plan saved to ${PLAN_FILE}${NC}"
