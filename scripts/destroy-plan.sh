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

echo -e "${BLUE}[*] Generating destroy plan for environment: ${ENV}${NC}"
cd "${TF_DIR}"

if [[ ! -f "terraform.tfvars" ]]; then
  echo -e "${RED}[!] Missing terraform.tfvars file. Aborting.${NC}"
  exit 1
fi

mkdir -p "${PLAN_DIR}"

echo -e "${BLUE}[*] Initializing Terraform (init modules and backend)...${NC}"
terraform init -upgrade -input=false

echo -e "${BLUE}[*] Formatting Terraform files...${NC}"
terraform fmt -recursive

echo -e "${BLUE}[*] Validating Terraform configuration...${NC}"
terraform validate && echo -e "${GREEN}[✔] Validation passed${NC}"

if [[ -f "${PLAN_FILE}" ]]; then
  echo -e "${BLUE}[*] Existing plan '${PLAN_FILE}' found. Deleting it...${NC}"
  rm -f "${PLAN_FILE}"
fi

echo -e "${BLUE}[*] Saving destroy plan to '${PLAN_FILE}'...${NC}"
terraform plan -destroy -var-file="terraform.tfvars" -out="${PLAN_FILE}"
echo -e "${GREEN}[✔] Destroy plan saved to ${PLAN_FILE}${NC}"
