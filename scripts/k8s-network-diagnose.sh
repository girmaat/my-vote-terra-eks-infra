#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE=${1:-default}
echo -e "${BLUE}🌐 Starting advanced networking diagnostics for namespace: $NAMESPACE${NC}"
echo "==========================================================================="

pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '{print $1}')
services=$(kubectl get svc -n "$NAMESPACE" --no-headers | awk '{print $1}')
network_policies=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)

# DNS, Service Reachability, and Port Matching
for pod in $pods; do
  echo ""
  echo -e "${BLUE}🔍 Pod: $pod${NC}"
  echo "--------------------------------------------------"

  # DNS Test
  DNS_RESULT=$(kubectl exec "$pod" -n "$NAMESPACE" -- nslookup kubernetes.default 2>/dev/null)
  if [[ "$DNS_RESULT" == *"Name:"* ]]; then
    echo -e "${GREEN}✅ DNS resolution working${NC}"
  else
    echo -e "${RED}❗ DNS resolution failed${NC}"
    echo -e "${YELLOW}👉 Check CoreDNS logs: kubectl logs -n kube-system -l k8s-app=kube-dns${NC}"
  fi

  # Curl Service Check (ClusterIP reach)
  for svc in $services; do
    REACH=$(kubectl exec "$pod" -n "$NAMESPACE" -- sh -c "timeout 2 curl -s http://$svc:80" 2>/dev/null)
    if [[ -z "$REACH" ]]; then
      echo -e "${YELLOW}⚠️ Pod cannot reach service $svc on port 80${NC}"
    else
      echo -e "${GREEN}✅ Pod can reach service $svc:80${NC}"
    fi
  done
done

# Service-to-Pod Mapping & Port Matching
echo ""
echo -e "${BLUE}🔎 Checking Service endpoint and port integrity...${NC}"
echo "==========================================================="

for svc in $services; do
  echo ""
  echo -e "${BLUE}🔧 Service: $svc${NC}"
  SELECTOR=$(kubectl get svc "$svc" -n "$NAMESPACE" -o jsonpath='{.spec.selector}')
  if [[ -z "$SELECTOR" ]]; then
    echo -e "${YELLOW}⚠️ No selector set. Headless or ExternalName?${NC}"
    continue
  fi

  ENDPOINTS=$(kubectl get endpoints "$svc" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}')
  if [[ -z "$ENDPOINTS" ]]; then
    echo -e "${RED}❗ No endpoints. Service has no backing pods.${NC}"
    echo -e "${BLUE}👉 Check pod labels or deployment readiness.${NC}"
  else
    echo -e "${GREEN}✅ Service has active endpoints${NC}"
  fi

  TARGET_PORT=$(kubectl get svc "$svc" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].targetPort}')
  SELECTOR_KEY=$(kubectl get svc "$svc" -n "$NAMESPACE" -o jsonpath='{range $k,$v := .spec.selector}{$k}={$v},{end}' | sed 's/,$//')
  POD_MATCH=$(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR_KEY" -o jsonpath='{.items[0].spec.containers[0].ports[0].containerPort}' 2>/dev/null)

  if [[ "$TARGET_PORT" != "$POD_MATCH" ]]; then
    echo -e "${YELLOW}⚠️ Port mismatch: targetPort=$TARGET_PORT, containerPort=$POD_MATCH${NC}"
  else
    echo -e "${GREEN}✅ Port alignment OK (targetPort=$TARGET_PORT)${NC}"
  fi
done

# NetworkPolicy Analysis
echo ""
echo -e "${BLUE}🔐 NetworkPolicy status check...${NC}"
if [[ "$network_policies" -eq 0 ]]; then
  echo -e "${YELLOW}⚠️ No NetworkPolicies exist. Namespace traffic is unrestricted.${NC}"
else
  echo -e "${GREEN}✅ $network_policies NetworkPolicies detected${NC}"
  echo -e "${YELLOW}📌 Verify they allow ingress/egress as expected${NC}"
fi

# Ingress Route Test (basic simulation)
INGRESS=$(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}')
if [[ -n "$INGRESS" ]]; then
  echo ""
  echo -e "${BLUE}🌐 Found Ingress: $INGRESS — Simulating HTTP test (optional)...${NC}"
  HOST=$(kubectl get ingress "$INGRESS" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}')
  if [[ -n "$HOST" ]]; then
    curl_output=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://$HOST")
    if [[ "$curl_output" == "200" ]]; then
      echo -e "${GREEN}✅ Ingress route returned HTTP 200${NC}"
    else
      echo -e "${YELLOW}⚠️ Ingress returned status $curl_output — check backend service and path${NC}"
    fi
  else
    echo -e "${YELLOW}⚠️ Ingress host not set — skip external route test${NC}"
  fi
else
  echo ""
  echo -e "${YELLOW}⚠️ No Ingress objects found in this namespace.${NC}"
fi

# Service Type Analysis
echo ""
echo -e "${BLUE}🛠 Analyzing Service types...${NC}"
kubectl get svc -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip --no-headers | while read -r line; do
  NAME=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{print $2}')
  EXT_IP=$(echo $line | awk '{print $4}')

  case "$TYPE" in
    LoadBalancer)
      if [[ -z "$EXT_IP" || "$EXT_IP" == "<none>" ]]; then
        echo -e "${RED}❗ LoadBalancer service $NAME has no external IP${NC}"
      else
        echo -e "${GREEN}✅ LoadBalancer $NAME is exposed at $EXT_IP${NC}"
      fi
      ;;
    NodePort)
      echo -e "${YELLOW}⚠️ NodePort service $NAME may require firewall or node IP access${NC}"
      ;;
    ExternalName)
      echo -e "${BLUE}🔗 ExternalName service $NAME redirects to external DNS name${NC}"
      ;;
    *)
      echo -e "${GREEN}✅ Service $NAME (type=$TYPE) is valid${NC}"
      ;;
  esac
done

# Duplicate endpoint IP check
echo ""
echo -e "${BLUE}🧪 Scanning for duplicate endpoint IPs...${NC}"
DUPES=$(kubectl get endpoints -n "$NAMESPACE" -o jsonpath='{.items[*].subsets[*].addresses[*].ip}' | tr ' ' '\n' | sort | uniq -d)
if [[ -n "$DUPES" ]]; then
  echo -e "${RED}❗ Duplicate endpoint IPs detected:${NC} $DUPES"
  echo -e "${YELLOW}👉 May indicate misconfigured selectors or replica conflict${NC}"
else
  echo -e "${GREEN}✅ No duplicate endpoint IPs found${NC}"
fi

echo ""
echo -e "${GREEN}✅ Full networking diagnostics complete for namespace: $NAMESPACE${NC}"
