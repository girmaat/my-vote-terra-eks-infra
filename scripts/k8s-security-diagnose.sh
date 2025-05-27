#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE=${1:-default}
AUTO_FIX=false
if [[ "$2" == "--fix" ]]; then
  AUTO_FIX=true
fi

echo -e "${BLUE}🔐 Running Kubernetes security diagnostics in namespace: $NAMESPACE${NC}"
echo "======================================================================"

# Cluster-wide OIDC provider check (once)
OIDC_URL=$(aws eks describe-cluster --name "$(kubectl config current-context | awk -F'@' '{print $2}')" --query "cluster.identity.oidc.issuer" --output text 2>/dev/null)
if [[ -z "$OIDC_URL" || "$OIDC_URL" == "None" ]]; then
  echo -e "${RED}❗ No OIDC provider detected for EKS cluster. IRSA will not work.${NC}"
else
  echo -e "${GREEN}✅ OIDC Provider is configured:${NC} $OIDC_URL"
fi

# Map ServiceAccounts for usage count
declare -A SA_USAGE
for sa in $(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].spec.serviceAccountName}'); do
  ((SA_USAGE["$sa"]++))
done

pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '{print $1}')

for pod in $pods; do
  echo ""
  echo -e "${BLUE}🔍 Inspecting Pod: $pod${NC}"
  echo "--------------------------------------------------"

  SA_NAME=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.serviceAccountName}')
  TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"

  # Warn if SA is reused
  if [[ "${SA_USAGE[$SA_NAME]}" -gt 1 ]]; then
    echo -e "${YELLOW}⚠️ ServiceAccount '$SA_NAME' is shared by ${SA_USAGE[$SA_NAME]} pods.${NC}"
  fi

  # Check IRSA annotation
  IRSA_ROLE=$(kubectl get sa "$SA_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)
  if [[ -z "$IRSA_ROLE" ]]; then
    echo -e "${RED}❗ Missing IRSA annotation on ServiceAccount: $SA_NAME${NC}"
    if $AUTO_FIX; then
      read -p "🔧 Enter IAM Role ARN to patch IRSA (or leave blank to skip): " input_role
      if [[ -n "$input_role" ]]; then
        kubectl annotate sa "$SA_NAME" -n "$NAMESPACE" "eks.amazonaws.com/role-arn=$input_role" --overwrite
        echo -e "${GREEN}✅ IRSA annotation applied to $SA_NAME${NC}"
      else
        echo -e "${YELLOW}⏭️ Skipped annotation.${NC}"
      fi
    else
      echo -e "${BLUE}👉 Manual fix:${NC} kubectl annotate sa $SA_NAME -n $NAMESPACE eks.amazonaws.com/role-arn=<your-iam-role-arn>"
    fi
  else
    echo -e "${GREEN}✅ IRSA Role ARN:${NC} $IRSA_ROLE"

    # Validate IAM trust policy if IRSA role is present
    ROLE_NAME=$(basename "$IRSA_ROLE")
    TRUSTED_OIDC=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.AssumeRolePolicyDocument.Statement[0].Principal.Federated" --output text 2>/dev/null)
    if [[ "$TRUSTED_OIDC" != *"oidc"* ]]; then
      echo -e "${RED}❗ IAM role '$ROLE_NAME' does not trust an OIDC provider.${NC}"
      echo -e "${BLUE}👉 Fix:${NC} Update trust policy in AWS IAM console to trust OIDC URL: $OIDC_URL"
    else
      echo -e "${GREEN}✅ IAM Trust Policy is correctly configured for IRSA.${NC}"
    fi
  fi

  # Token mount check
  TOKEN_EXISTS=$(kubectl exec "$pod" -n "$NAMESPACE" -- sh -c "[ -f $TOKEN_PATH ] && echo yes || echo no" 2>/dev/null)
  if [[ "$TOKEN_EXISTS" == "yes" ]]; then
    echo -e "${GREEN}✅ ServiceAccount token is mounted${NC}"

    # Decode JWT and show expiration
    EXP_RAW=$(kubectl exec "$pod" -n "$NAMESPACE" -- sh -c "cut -d. -f2 $TOKEN_PATH | base64 -d 2>/dev/null | jq -r .exp" 2>/dev/null)
    if [[ "$EXP_RAW" =~ ^[0-9]+$ ]]; then
      EXP_DATE=$(date -d @"$EXP_RAW")
      echo -e "${BLUE}📅 Token expires at:${NC} $EXP_DATE"
    fi
  else
    echo -e "${RED}❗ Token not mounted in pod.${NC}"
    echo -e "${YELLOW}📌 Likely reason: automountServiceAccountToken: false${NC}"
    echo -e "${BLUE}👉 Fix: add 'automountServiceAccountToken: true' in your pod/deployment spec.${NC}"
  fi

  # IAM identity test
  echo -e "${BLUE}🔄 Testing AWS identity...${NC}"
  STS=$(kubectl exec "$pod" -n "$NAMESPACE" -- sh -c "command -v aws" 2>/dev/null)
  if [[ -z "$STS" ]]; then
    echo -e "${YELLOW}⚠️ awscli is not installed in this container — skipping STS check.${NC}"
  else
    IAM_RESULT=$(kubectl exec "$pod" -n "$NAMESPACE" -- aws sts get-caller-identity --output json 2>/dev/null)
    if [[ -n "$IAM_RESULT" ]]; then
      echo -e "${GREEN}✅ IAM identity is valid:${NC}"
      echo "$IAM_RESULT" | jq
    else
      echo -e "${RED}❗ AWS STS call failed.${NC}"
      echo -e "${YELLOW}👉 Possible causes:${NC}"
      echo "   - Role not trusted"
      echo "   - Pod not using IRSA"
      echo "   - Missing AWS permissions"
    fi
  fi

  # RBAC inspection
  RBINDINGS=$(kubectl get rolebinding,clusterrolebinding -A --field-selector=subjects[0].name="$SA_NAME" -o name 2>/dev/null)
  if [[ -n "$RBINDINGS" ]]; then
    echo -e "${GREEN}✅ ServiceAccount is bound to RBAC roles:${NC}"
    echo "$RBINDINGS"
  else
    echo -e "${YELLOW}⚠️ No RoleBinding or ClusterRoleBinding found for SA '$SA_NAME'.${NC}"
    echo -e "${BLUE}👉 Fix: Create appropriate RoleBinding to give permissions.${NC}"
  fi

  # Warn if sensitive env vars are exposed
  ENV_VARS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].env[*].name}')
  for var in $ENV_VARS; do
    if [[ "$var" =~ (SECRET|KEY|TOKEN|PASS|PWD) ]]; then
      echo -e "${RED}❗ Potential exposed sensitive variable: $var${NC}"
      echo -e "${BLUE}👉 Use Kubernetes Secrets instead of plaintext values.${NC}"
    fi
  done
done

echo ""
echo -e "${GREEN}✅ Security diagnostics complete for namespace: $NAMESPACE${NC}"
echo -e "${BLUE}📌 Tip:${NC} Use ${YELLOW}--fix${NC} to patch missing IRSA annotations."
