#!/bin/bash

# Install and start SSM Agent
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Fetch cluster data dynamically
REGION="us-east-1"
CLUSTER="my-vote-dev"

API_ENDPOINT=$(aws eks describe-cluster \
  --name $CLUSTER \
  --region $REGION \
  --query "cluster.endpoint" --output text)

CLUSTER_CA=$(aws eks describe-cluster \
  --name $CLUSTER \
  --region $REGION \
  --query "cluster.certificateAuthority.data" --output text)

/etc/eks/bootstrap.sh $CLUSTER \
  --apiserver-endpoint "$API_ENDPOINT" \
  --b64-cluster-ca "$CLUSTER_CA" \
  --kubelet-extra-args '--node-labels=eks/self-managed=true'
