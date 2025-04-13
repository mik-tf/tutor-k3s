#!/bin/bash
# Simple wrapper script to create or verify namespaces using kubectl directly
# This avoids Ansible K8s module connectivity issues

set -e

NAMESPACE="$1"
ACTION="$2"

if [ "$ACTION" == "create" ]; then
  kubectl get namespace "$NAMESPACE" 2>/dev/null || kubectl create namespace "$NAMESPACE"
  echo "Namespace $NAMESPACE exists"
elif [ "$ACTION" == "check" ]; then
  kubectl get namespace "$NAMESPACE" 2>/dev/null
  echo "$?"
else
  echo "Unknown action: $ACTION"
  exit 1
fi
