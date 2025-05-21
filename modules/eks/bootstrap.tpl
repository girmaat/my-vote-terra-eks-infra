#!/bin/bash
set -o xtrace

# Load required kernel modules
modprobe br_netfilter
echo 'br_netfilter' > /etc/modules-load.d/br_netfilter.conf

# Apply sysctl settings immediately and persistently
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.bridge.bridge-nf-call-iptables=1

cat <<EOF > /etc/sysctl.d/99-eks.conf
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
EOF

# Ensure all sysctl settings are applied system-wide
sysctl --system

# Wait for IMDS (instance metadata service) to be reachable before CNI starts
for i in {1..10}; do
  if curl -s --connect-timeout 1 http://169.254.169.254/latest/meta-data/; then
    echo "✅ IMDS reachable"
    break
  else
    echo "⏳ Waiting for IMDS (try $i)..."
    sleep 3
  fi
done

# Bootstrap the node into the EKS cluster
/etc/eks/bootstrap.sh ${cluster_name} \
  --kubelet-extra-args '--node-labels=eks/self-managed=true' \
  --b64-cluster-ca ${cluster_ca} \
  --apiserver-endpoint ${cluster_endpoint}
