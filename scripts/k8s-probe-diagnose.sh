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

echo -e "${BLUE}🩺 Starting probe & health check diagnostics in namespace: $NAMESPACE${NC}"
echo "==========================================================================="

pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '{print $1}')

for pod in $pods; do
  echo ""
  echo -e "${BLUE}🔍 Inspecting Pod: $pod${NC}"
  echo "--------------------------------------------------"

  DESCRIBE=$(kubectl describe pod "$pod" -n "$NAMESPACE")

  # Check readiness
  if echo "$DESCRIBE" | grep -q "Readiness probe failed"; then
    echo -e "${RED}❗ Readiness probe failing${NC}"
  else
    echo -e "${GREEN}✅ Readiness probe is passing${NC}"
  fi

  # Check liveness
  if echo "$DESCRIBE" | grep -q "Liveness probe failed"; then
    echo -e "${RED}❗ Liveness probe is failing — pod may be restarting${NC}"
  else
    echo -e "${GREEN}✅ Liveness probe is passing${NC}"
  fi

  DEPLOYMENT=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].name}')
  CONTAINER_NAME=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].name}')
  PATH=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].readinessProbe.httpGet.path}')
  PORT=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].readinessProbe.httpGet.port}')
  INIT_DELAY=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].readinessProbe.initialDelaySeconds}')
  STARTUP_PROBE=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].startupProbe.httpGet.path}' 2>/dev/null)

  # Simulate probe endpoint
  if [[ -n "$PATH" && -n "$PORT" ]]; then
    curl_output=$(kubectl exec "$pod" -c "$CONTAINER_NAME" -n "$NAMESPACE" -- curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT$PATH")
    if [[ "$curl_output" == "200" ]]; then
      echo -e "${GREEN}✅ Probe endpoint returned 200 OK${NC}"
    else
      echo -e "${RED}❗ Probe endpoint returned $curl_output${NC}"
    fi
  else
    echo -e "${YELLOW}⚠️ No HTTP probe path or port found — may be TCP or exec probe${NC}"
  fi

  # Fixes
  if $AUTO_FIX; then
    echo -e "${YELLOW}🔧 Fix mode enabled for pod: $pod (from deployment: $DEPLOYMENT)${NC}"

    # 1. Patch initialDelaySeconds if <10
    if [[ "$INIT_DELAY" -lt 10 ]]; then
      read -p "🔁 Increase initialDelaySeconds to 10? (y/n): " confirm_delay
      if [[ "$confirm_delay" == "y" ]]; then
        kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" \
          --type='json' \
          -p="[{'op': 'replace', 'path': '/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds', 'value':10}]"
        echo -e "${GREEN}✅ Patched initialDelaySeconds to 10s${NC}"
      else
        echo -e "${YELLOW}⏭️ Skipped delay patch.${NC}"
      fi
    fi

    # 2. Add startupProbe if missing
    if [[ -z "$STARTUP_PROBE" && -n "$PATH" && -n "$PORT" ]]; then
      read -p "🛠 Add startupProbe with same path/port as readiness? (y/n): " confirm_startup
      if [[ "$confirm_startup" == "y" ]]; then
        kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" \
          --type='json' \
          -p="[{
            'op': 'add',
            'path': '/spec/template/spec/containers/0/startupProbe',
            'value': {
              'httpGet': {
                'path': '$PATH',
                'port': $PORT
              },
              'initialDelaySeconds': 10,
              'periodSeconds': 5,
              'failureThreshold': 12
            }
          }]"
        echo -e "${GREEN}✅ Added startupProbe to deployment $DEPLOYMENT${NC}"
      else
        echo -e "${YELLOW}⏭️ Skipped adding startupProbe.${NC}"
      fi
    fi
  fi
done

echo ""
echo -e "${GREEN}✅ Probe diagnostics complete for namespace: $NAMESPACE${NC}"
echo -e "${BLUE}📌 Tip:${NC} Use ${YELLOW}--fix${NC} to patch readiness/startup probe settings."
