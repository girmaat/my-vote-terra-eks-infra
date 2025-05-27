#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE=${1:-default}
AUTO_FIX=false
if [[ "$2" == "--fix" ]]; then
  AUTO_FIX=true
fi

echo -e "${BLUE}🔍 Starting configuration & scheduling diagnostics in namespace: $NAMESPACE${NC}"
echo "=============================================================================="

pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '{print $1}')
for pod in $pods; do
  echo ""
  echo -e "${BLUE}📦 Inspecting pod: $pod${NC}"
  echo "--------------------------------------------------"

  # Check if pod is Pending
  STATUS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
  if [[ "$STATUS" == "Pending" ]]; then
    echo -e "${RED}❗ Pod is stuck in Pending state.${NC}"
    echo -e "${BLUE}🔍 Events:${NC}"
    kubectl describe pod "$pod" -n "$NAMESPACE" | grep -A 5 "Events"
  fi

  # Check recent termination
  EXIT_CODE=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}' 2>/dev/null)
  if [[ "$EXIT_CODE" == "1" ]]; then
    echo -e "${RED}❗ Pod exited with code 1 — possible bad command or startup failure.${NC}"
    echo -e "${BLUE}👉 Check container spec, entrypoint, or required env/config values${NC}"
  fi

  # Check missing configMaps/secrets
  echo -e "${BLUE}🔎 Validating configMap and secret references...${NC}"
  CM_REFS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o json | jq -r '.spec.containers[].envFrom[]?.configMapRef.name // empty')
  for cm in $CM_REFS; do
    if ! kubectl get configmap "$cm" -n "$NAMESPACE" &>/dev/null; then
      echo -e "${RED}❗ Missing ConfigMap: $cm${NC}"
      if $AUTO_FIX; then
        read -p "🛠 Create placeholder ConfigMap '$cm'? (y/n): " confirm
        [[ "$confirm" == "y" ]] && kubectl create configmap "$cm" -n "$NAMESPACE"
      fi
    fi
  done

  SEC_REFS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o json | jq -r '.spec.containers[].envFrom[]?.secretRef.name // empty')
  for sec in $SEC_REFS; do
    if ! kubectl get secret "$sec" -n "$NAMESPACE" &>/dev/null; then
      echo -e "${RED}❗ Missing Secret: $sec${NC}"
      if $AUTO_FIX; then
        read -p "🛠 Create placeholder Secret '$sec'? (y/n): " confirm
        [[ "$confirm" == "y" ]] && kubectl create secret generic "$sec" -n "$NAMESPACE"
      fi
    fi
  done

  # PVC check
  VOLUMES=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[*].persistentVolumeClaim.claimName}')
  for pvc in $VOLUMES; do
    if [[ -n "$pvc" && ! $(kubectl get pvc "$pvc" -n "$NAMESPACE" 2>/dev/null) ]]; then
      echo -e "${RED}❗ Missing PVC: $pvc${NC}"
      echo -e "${BLUE}👉 Create PVC or verify storage class setup${NC}"
    fi
  done

  # Scheduling diagnostics (affinity, taints)
  AFFINITY=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[*].matchExpressions[*].key}' 2>/dev/null)
  if [[ -n "$AFFINITY" ]]; then
    echo -e "${YELLOW}⚠️ Node affinity is configured — may restrict scheduling${NC}"
    echo -e "${BLUE}   Affinity key: $AFFINITY${NC}"
  fi

  TOLERATIONS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.tolerations[*].key}' 2>/dev/null)
  TAINTED_NODES=$(kubectl get nodes -o json | jq -r '.items[].spec.taints[]?.key // empty')

  if [[ -n "$TAINTED_NODES" && -z "$TOLERATIONS" ]]; then
    echo -e "${RED}❗ Tainted nodes exist, but pod has no tolerations.${NC}"
    if $AUTO_FIX; then
      read -p "🛠 Patch toleration to allow scheduling? (y/n): " confirm
      if [[ "$confirm" == "y" ]]; then
        DEPLOYMENT=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].name}')
        kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" \
          --type='json' \
          -p="[{'op': 'add', 'path': '/spec/template/spec/tolerations', 'value':[{'key':'${TAINTED_NODES%% *}','operator':'Exists','effect':'NoSchedule'}]}]"
        echo -e "${GREEN}✅ Toleration patched into deployment.${NC}"
      fi
    fi
  fi

  # Resource request check
  echo -e "${BLUE}🧮 Checking resource requests against node capacity...${NC}"
  CPU_REQ=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.requests.cpu}')
  MEM_REQ=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.requests.memory}')
  NODES=$(kubectl get nodes -o json)

  for node in $(echo "$NODES" | jq -r '.items[].metadata.name'); do
    CPU_AVAIL=$(echo "$NODES" | jq -r ".items[] | select(.metadata.name==\"$node\") | .status.allocatable.cpu")
    MEM_AVAIL=$(echo "$NODES" | jq -r ".items[] | select(.metadata.name==\"$node\") | .status.allocatable.memory")

    if [[ "$CPU_REQ" > "$CPU_AVAIL" || "$MEM_REQ" > "$MEM_AVAIL" ]]; then
      echo -e "${RED}❗ Resource requests too high for node $node${NC}"
      echo -e "${BLUE}👉 CPU: $CPU_REQ / $CPU_AVAIL, MEM: $MEM_REQ / $MEM_AVAIL${NC}"
      echo -e "${YELLOW}🛠 Suggest reducing requests or scaling up node size${NC}"
    fi
  done
done

echo ""
echo -e "${GREEN}✅ Configuration and scheduling diagnostics complete for namespace: $NAMESPACE${NC}"
echo -e "${BLUE}📌 Tip: Use ${YELLOW}--fix${NC} to auto-create config objects or patch tolerations."
