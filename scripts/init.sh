#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
DIR="environments/${ENV}"

GREEN='\033[0;32m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}[*] Initializing Terraform for environment: ${ENV}${NC}"
cd "${DIR}"

if [[ ! -f backend.tf ]]; then
  echo -e "${RED}[!] backend.tf not found in ${DIR}${NC}"
  exit 1
fi

terraform init
