#!/bin/bash

# Color codes
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

echo -e "${BLUE}🚀 Diagnosing Kubernetes pods in namespace: $NAMESPACE${NC}"
echo "========================================================="

pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '{print $1}')

for pod in $pods; do
  echo ""
  echo -e "${BLUE}🔍 Inspecting Pod: $pod${NC}"
  echo "--------------------------------------------------"

  IS_TERMINATING=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.metadata.deletionTimestamp}')
  if [[ -n "$IS_TERMINATING" ]]; then
    echo -e "${YELLOW}⏳ Pod is terminating... skipping.${NC}"
    continue
  fi

  STATUS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
  REASON=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
  REASON=${REASON:-None}
  RESTARTS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
  LAST_STATE=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null)

  echo -e "${BLUE}📝 Status:${NC} $STATUS"
  [[ "$REASON" != "None" ]] && echo -e "${BLUE}🧾 Reason:${NC} $REASON"
  echo -e "${BLUE}🔁 Restart count:${NC} ${RESTARTS:-0}"

  if [[ "$REASON" == "CrashLoopBackOff" ]]; then
    echo -e "${RED}❗ CrashLoopBackOff: Pod is crashing repeatedly.${NC}"
    if $AUTO_FIX; then
      read -p "🔧 Delete pod $pod to force restart? (y/n): " confirm
      if [[ $confirm == "y" ]]; then
        kubectl delete pod "$pod" -n "$NAMESPACE"
        echo -e "${GREEN}✅ Pod deleted. Controller will recreate it.${NC}"
      else
        echo -e "${YELLOW}⏭️ Skipped deleting pod.${NC}"
      fi
    else
      echo -e "${BLUE}👉 Run manually:${NC} kubectl delete pod $pod -n $NAMESPACE"
      echo -e "${BLUE}👉 Check logs:${NC} kubectl logs --previous $pod -n $NAMESPACE"
    fi
    continue
  fi

  if [[ "$REASON" == "ImagePullBackOff" || "$REASON" == "ErrImagePull" ]]; then
    IMAGE=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].image}')
    echo -e "${RED}❗ Image pull error: Failed to pull image: $IMAGE${NC}"
    echo -e "${BLUE}👉 Describe pod:${NC} kubectl describe pod $pod -n $NAMESPACE"
    echo -e "${BLUE}👉 Check image name, tag, or registry credentials${NC}"
    echo -e "${YELLOW}🔧 Fix: update Deployment/StatefulSet and reapply${NC}"
    continue
  fi

  if [[ "$LAST_STATE" == "OOMKilled" ]]; then
    echo -e "${RED}❗ OOMKilled: Container exceeded memory limit.${NC}"
    echo -e "${BLUE}👉 Suggested fix:${NC}"
    echo "   - kubectl edit deployment <name> -n $NAMESPACE"
    echo "   - Increase memory limit in 'resources.limits.memory'"
    continue
  fi

  if [[ "$REASON" == "ContainerCreating" ]]; then
    echo -e "${YELLOW}⚠️ Container is stuck in creating state.${NC}"
    echo -e "${BLUE}👉 Run:${NC} kubectl describe pod $pod -n $NAMESPACE | grep -A 5 Events"
    continue
  fi

  if [[ "$STATUS" == "Pending" ]]; then
    echo -e "${RED}❗ Pod is Pending — likely a scheduler constraint.${NC}"
    echo -e "${BLUE}👉 Run:${NC} kubectl describe pod $pod -n $NAMESPACE"
    echo -e "${BLUE}👉 Check:${NC} affinity, taints, resource limits, missing PVCs"
    continue
  fi

  if [[ "$STATUS" == "Running" && "$RESTARTS" -gt 0 ]]; then
    echo -e "${YELLOW}⚠️ Pod is running but has restarted $RESTARTS times.${NC}"
    if [[ "$RESTARTS" -ge 3 && "$AUTO_FIX" = true ]]; then
      read -p "🔄 Restart pod $pod to reset state? (y/n): " confirm
      if [[ $confirm == "y" ]]; then
        kubectl delete pod "$pod" -n "$NAMESPACE"
        echo -e "${GREEN}✅ Pod deleted to force clean restart.${NC}"
      else
        echo -e "${YELLOW}⏭️ Skipped pod deletion.${NC}"
      fi
    else
      echo -e "${BLUE}👉 Review logs:${NC} kubectl logs $pod -n $NAMESPACE"
      echo -e "${BLUE}👉 Consider tuning probes or memory limits${NC}"
    fi
    continue
  fi

  if [[ "$STATUS" == "Running" && "$RESTARTS" -eq 0 ]]; then
    echo -e "${GREEN}✅ Pod is healthy and running normally.${NC}"
  else
    echo -e "${YELLOW}⚠️ Pod is in unusual state: $STATUS${NC}"
  fi
done

echo ""
echo -e "${BLUE}📦 Scanning Jobs for failure in namespace: $NAMESPACE${NC}"
echo "========================================================="

jobs=$(kubectl get jobs -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}')

for job in $jobs; do
  completions=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null)
  failures=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.status.failed}' 2>/dev/null)
  backoffLimit=$(kubectl get job "$job" -n "$NAMESPACE" -o jsonpath='{.spec.backoffLimit}' 2>/dev/null)

  if [[ -n "$failures" && -n "$backoffLimit" && "$failures" -ge "$backoffLimit" ]]; then
    echo -e "${RED}❌ Job $job failed (failures: $failures / backoffLimit: $backoffLimit)${NC}"

    if $AUTO_FIX; then
      read -p "🔄 Do you want to delete and retry Job $job? (y/n): " confirm
      if [[ "$confirm" == "y" ]]; then
        kubectl delete job "$job" -n "$NAMESPACE"
        echo -e "${GREEN}✅ Job deleted. Reapply manifest to retry.${NC}"
        echo -e "${BLUE}📌 Reminder:${NC} kubectl apply -f manifests/jobs/$job.yaml"
      else
        echo -e "${YELLOW}⏭️ Skipped retrying job.${NC}"
      fi
    else
      echo -e "${BLUE}👉 To retry manually:${NC}"
      echo "    kubectl delete job $job -n $NAMESPACE"
      echo "    kubectl apply -f manifests/jobs/$job.yaml"
    fi
  fi
done

echo ""
echo -e "${GREEN}✅ Diagnostics complete for namespace: $NAMESPACE${NC}"
echo -e "${BLUE}📌 Tip:${NC} Run again with '${YELLOW}--fix${NC}' to attempt safe automated repairs."
