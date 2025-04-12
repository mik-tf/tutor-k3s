#!/bin/bash
# OpenedX Cleanup and Diagnostics Script

set -e

# Ensure KUBECONFIG is set
KUBECONFIG_PATH=$(readlink -f "../config/k3s.yaml")
export KUBECONFIG=$KUBECONFIG_PATH

echo "=== Checking cluster resources ==="
echo "Node resources:"
kubectl describe nodes | grep -A 8 "Allocated resources"

echo -e "\n=== Stuck pods in Terminating state ==="
STUCK_PODS=$(kubectl get pods -n openedx | grep Terminating | awk '{print $1}')
if [ ! -z "$STUCK_PODS" ]; then
  echo "Found pods stuck in Terminating state. Force deleting them..."
  for pod in $STUCK_PODS; do
    echo "Force deleting pod: $pod"
    kubectl delete pod -n openedx $pod --force --grace-period=0
  done
else
  echo "No stuck pods found."
fi

echo -e "\n=== Pods with ImagePullBackOff errors ==="
IMAGE_PULL_ISSUES=$(kubectl get pods -n openedx | grep ImagePullBackOff | awk '{print $1}')
if [ ! -z "$IMAGE_PULL_ISSUES" ]; then
  echo "Found pods with ImagePullBackOff. Recreating them..."
  for pod in $IMAGE_PULL_ISSUES; do
    echo "Deleting pod: $pod"
    kubectl delete pod -n openedx $pod
  done
else
  echo "No ImagePullBackOff errors found."
fi

echo -e "\n=== Checking Docker registry credentials ==="
kubectl get secret -n openedx dockerhub-creds -o json | jq '.data[".dockerconfigjson"]' -r | base64 --decode | jq .

echo -e "\n=== Current Persistent Volume Claims ==="
kubectl get pvc -n openedx

echo -e "\n=== Reducing resource requirements ==="
TUTOR_BIN="../venv/bin/tutor"

# Set lower resource requirements
echo "Configuring minimal resource requirements..."
$TUTOR_BIN config save --set K8S_RESOURCES_REQUESTS_ENABLED=false
$TUTOR_BIN config save --set K8S_RESOURCES_LIMITS_ENABLED=true
$TUTOR_BIN config save --set K8S_RESOURCES_LMS_LIMITS_CPU=1
$TUTOR_BIN config save --set K8S_RESOURCES_LMS_LIMITS_MEMORY=1Gi
$TUTOR_BIN config save --set K8S_RESOURCES_CMS_LIMITS_CPU=1
$TUTOR_BIN config save --set K8S_RESOURCES_CMS_LIMITS_MEMORY=1Gi
$TUTOR_BIN config save --set K8S_RESOURCES_MYSQL_LIMITS_CPU=0.5
$TUTOR_BIN config save --set K8S_RESOURCES_MYSQL_LIMITS_MEMORY=512Mi
$TUTOR_BIN config save --set K8S_RESOURCES_MONGODB_LIMITS_CPU=0.5
$TUTOR_BIN config save --set K8S_RESOURCES_MONGODB_LIMITS_MEMORY=512Mi
$TUTOR_BIN config save --set K8S_RESOURCES_ELASTICSEARCH_LIMITS_CPU=0.5
$TUTOR_BIN config save --set K8S_RESOURCES_ELASTICSEARCH_LIMITS_MEMORY=1Gi
$TUTOR_BIN config save --set K8S_RESOURCES_REDIS_LIMITS_CPU=0.3
$TUTOR_BIN config save --set K8S_RESOURCES_REDIS_LIMITS_MEMORY=256Mi

echo -e "\n=== Fixing Docker registry authentication ==="
kubectl delete secret -n openedx dockerhub-creds --ignore-not-found
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: dockerhub-creds
  namespace: openedx
  annotations:
    kubernetes.io/description: "Docker registry credentials for accessing Open edX images"
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $(
    echo "{\"auths\": {\"docker.io\": {\"username\": \"${DOCKER_USERNAME}\", \"password\": \"${DOCKER_TOKEN}\", \"email\": \"${DOCKER_EMAIL}\"}}}" | base64 -w 0
  )
EOF

echo -e "\n=== Patching service accounts to use registry credentials ==="
for sa in default lms cms mfe; do
  kubectl patch serviceaccount $sa -n openedx -p '{"imagePullSecrets": [{"name": "dockerhub-creds"}]}'
done

echo -e "\n=== You can now run 'make deploy' again ==="
