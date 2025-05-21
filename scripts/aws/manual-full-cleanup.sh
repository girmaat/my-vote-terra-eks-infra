#!/bin/bash
set -euo pipefail

ENV="${1:-dev}"
CLUSTER_NAME="my-vote-${ENV}"
AWS_REGION="us-east-1"
TAG_FILTER="my-vote"

RED='\033[0;31m'
BLUE='\033[1;34m'
GREEN='\033[0;32m'
NC='\033[0m'

confirm() {
  echo -e "${RED}This will permanently delete AWS resources for '${ENV}' tagged or named with '${TAG_FILTER}'."
  read -p "Type 'yes' to proceed: " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "${RED}Aborted.${NC}"
    exit 1
  fi
}

delete_eks_cluster() {
  echo -e "${BLUE}Deleting EKS cluster: ${CLUSTER_NAME}${NC}"
  if aws eks delete-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION"; then
    echo -e "${BLUE}[*] Waiting for EKS cluster '${CLUSTER_NAME}' to be fully deleted...${NC}"
    aws eks wait cluster-deleted --name "$CLUSTER_NAME" --region "$AWS_REGION"
    echo -e "${GREEN}[✔] EKS cluster '${CLUSTER_NAME}' has been deleted.${NC}"
  else
    echo -e "${BLUE}[i] EKS cluster already deleted or not found.${NC}"
  fi
}

delete_ec2_instances() {
  echo -e "${BLUE}Terminating EC2 instances with tag 'Project=${TAG_FILTER}'...${NC}"
  INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=${TAG_FILTER}" \
    --region "$AWS_REGION" \
    --query "Reservations[].Instances[].InstanceId" --output text)

  if [[ -n "$INSTANCE_IDS" ]]; then
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region "$AWS_REGION" || true
    echo -e "${BLUE}[*] Waiting for EC2 instances to terminate...${NC}"
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region "$AWS_REGION"
  fi
}

delete_vpcs() {
  VPC_IDS=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=${TAG_FILTER}" \
    --region "$AWS_REGION" \
    --query "Vpcs[].VpcId" --output text)

  for VPC_ID in $VPC_IDS; do
    echo -e "${BLUE}Cleaning up VPC dependencies for $VPC_ID...${NC}"

    # Detach and delete NAT gateways
    NAT_IDS=$(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC_ID --region "$AWS_REGION" --query "NatGateways[].NatGatewayId" --output text)
    for NAT in $NAT_IDS; do
      echo -e "${BLUE}Deleting NAT Gateway: $NAT${NC}"
      aws ec2 delete-nat-gateway --nat-gateway-id "$NAT" --region "$AWS_REGION" || true
    done

    # Wait for NAT gateways to be deleted
    if [[ -n "$NAT_IDS" ]]; then
      echo -e "${BLUE}[*] Waiting for NAT gateways to be deleted...${NC}"
      for NAT in $NAT_IDS; do
        aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT" --region "$AWS_REGION"
      done
    fi

    # Delete network interfaces
    ENI_IDS=$(aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=$VPC_ID --region "$AWS_REGION" --query "NetworkInterfaces[].NetworkInterfaceId" --output text)
    for ENI in $ENI_IDS; do
      echo -e "${BLUE}Deleting ENI: $ENI${NC}"
      aws ec2 delete-network-interface --network-interface-id "$ENI" --region "$AWS_REGION" || true
    done

    # Disassociate and delete route tables
    RTB_IDS=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID --region "$AWS_REGION" --query "RouteTables[].RouteTableId" --output text)
    for RTB in $RTB_IDS; do
      ASSOCS=$(aws ec2 describe-route-tables --route-table-ids "$RTB" --region "$AWS_REGION" --query "RouteTables[].Associations[].RouteTableAssociationId" --output text)
      for A in $ASSOCS; do
        aws ec2 disassociate-route-table --association-id "$A" --region "$AWS_REGION" || true
      done
      # Skip main route table
      IS_MAIN=$(aws ec2 describe-route-tables --route-table-ids "$RTB" --region "$AWS_REGION" | jq '.RouteTables[].Associations[].Main')
      if [[ "$IS_MAIN" != "true" ]]; then
        aws ec2 delete-route-table --route-table-id "$RTB" --region "$AWS_REGION" || true
      fi
    done

    # Delete subnets
    SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --region "$AWS_REGION" --query "Subnets[].SubnetId" --output text)
    for SUBNET in $SUBNETS; do
      aws ec2 delete-subnet --subnet-id "$SUBNET" --region "$AWS_REGION" || true
    done

    # Detach and delete internet gateways
    IGWS=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC_ID --region "$AWS_REGION" --query "InternetGateways[].InternetGatewayId" --output text)
    for IGW in $IGWS; do
      aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_ID" --region "$AWS_REGION" || true
      aws ec2 delete-internet-gateway --internet-gateway-id "$IGW" --region "$AWS_REGION" || true
    done

    # Delete non-default security groups
    SG_IDS=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID --region "$AWS_REGION" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
    for SG in $SG_IDS; do
      aws ec2 delete-security-group --group-id "$SG" --region "$AWS_REGION" || true
    done

    # Finally delete the VPC
    echo -e "${BLUE}Deleting VPC: $VPC_ID${NC}"
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$AWS_REGION" || true
  done
}

delete_instance_profiles_and_roles() {
  echo -e "${BLUE}Deleting IAM instance profiles and roles matching '${CLUSTER_NAME}'...${NC}"

  PROFILES=$(aws iam list-instance-profiles --query "InstanceProfiles[?contains(InstanceProfileName, '${CLUSTER_NAME}')].InstanceProfileName" --output text)
  for PROFILE in $PROFILES; do
    ROLE_NAMES=$(aws iam get-instance-profile --instance-profile-name "$PROFILE" --query "InstanceProfile.Roles[].RoleName" --output text)
    for ROLE in $ROLE_NAMES; do
      aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE" || true
    done
    aws iam delete-instance-profile --instance-profile-name "$PROFILE" || true
  done

  ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, '${CLUSTER_NAME}')].RoleName" --output text)
  for ROLE in $ROLES; do
    POLICY_ARNS=$(aws iam list-attached-role-policies --role-name "$ROLE" --query "AttachedPolicies[].PolicyArn" --output text)
    for POLICY in $POLICY_ARNS; do
      aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY" || true
    done
    aws iam delete-role --role-name "$ROLE" || true
  done
}

delete_cloudwatch_logs() {
  echo -e "${BLUE}Deleting CloudWatch logs starting with '/aws/eks/${CLUSTER_NAME}'...${NC}"
  if ! aws logs describe-log-groups --log-group-name-prefix "/aws/eks/${CLUSTER_NAME}" --region "$AWS_REGION" > /dev/null 2>&1; then
    echo -e "${RED}[!] Skipping log deletion — not authorized (need logs:DescribeLogGroups).${NC}"
    return
  fi

  GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/eks/${CLUSTER_NAME}" --region "$AWS_REGION" --query "logGroups[].logGroupName" --output text)
  for GROUP in $GROUPS; do
    aws logs delete-log-group --log-group-name "$GROUP" --region "$AWS_REGION" || true
  done
}

### Run full cleanup
confirm
delete_eks_cluster
delete_ec2_instances
delete_vpcs
delete_instance_profiles_and_roles
delete_cloudwatch_logs

echo -e "${GREEN}[✔] Full AWS cleanup completed for environment '${ENV}'${NC}"
