#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh ${cluster_name} \
  --kubelet-extra-args '--node-labels=eks/self-managed=true' \
  --b64-cluster-ca ${cluster_ca} \
  --apiserver-endpoint ${cluster_endpoint}
