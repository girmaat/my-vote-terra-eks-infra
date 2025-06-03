#!/bin/bash

# Install and start SSM Agent
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

REGION="${region}"
CLUSTER="${cluster_name}"

# Endpoint and certificate authority are provided by Terraform
API_ENDPOINT="${cluster_endpoint}"
CLUSTER_CA="${cluster_ca}"

/etc/eks/bootstrap.sh $CLUSTER \
  --apiserver-endpoint "$API_ENDPOINT" \
  --b64-cluster-ca "$CLUSTER_CA" \
  --kubelet-extra-args '--node-labels=eks/self-managed=true'
