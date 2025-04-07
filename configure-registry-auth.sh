#!/bin/bash

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${YELLOW}=== Configuring Docker Registry Authentication ===${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace openedx &> /dev/null; then
    echo -e "${YELLOW}Creating openedx namespace...${NC}"
    kubectl create namespace openedx
fi

# Check for Docker Hub credentials in environment variables
if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_TOKEN" ] || [ -z "$DOCKER_EMAIL" ]; then
    echo -e "${YELLOW}Docker Hub credentials not found in environment variables.${NC}"
    echo -e "For secure credential handling, set them using:"
    echo -e "set +o history"
    echo -e "export DOCKER_USERNAME=\"your_dockerhub_username\""
    echo -e "export DOCKER_TOKEN=\"your_dockerhub_token\""
    echo -e "export DOCKER_EMAIL=\"your_email\""
    echo -e "set -o history"
    echo -e "\nNote: It's recommended to use a Docker Hub access token instead of your password."
    echo -e "You can create one at https://hub.docker.com/settings/security"
    echo -e "\nWhen creating your token, configure these permissions:"
    echo -e "- Set a descriptive name (e.g., 'K3s OpenEdX Deployment')"
    echo -e "- Set access permissions to 'Read-only' (minimum required)"
    echo -e "  * For public repositories, you can use 'Public repo read-only'"
    echo -e "- Set an appropriate expiration based on your security policies"
    
    # Prompt for credentials if not in environment
    read -p "Enter your Docker Hub username: " DOCKER_USERNAME
    read -sp "Enter your Docker Hub token/password: " DOCKER_TOKEN
    echo
    read -p "Enter your email address: " DOCKER_EMAIL
fi

echo -e "\n${YELLOW}Creating Docker Hub credentials secret...${NC}"
kubectl create secret docker-registry dockerhub-creds \
  --namespace openedx \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username="$DOCKER_USERNAME" \
  --docker-password="$DOCKER_TOKEN" \
  --docker-email="$DOCKER_EMAIL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo -e "\n${YELLOW}Configuring default service account to use the credentials...${NC}"
kubectl patch serviceaccount default \
  -n openedx \
  -p '{"imagePullSecrets": [{"name": "dockerhub-creds"}]}'

# Also patch the tutor-related service accounts if they exist
for sa in cms lms mfe; do
    if kubectl get serviceaccount $sa -n openedx &>/dev/null; then
        echo -e "Configuring $sa service account..."
        kubectl patch serviceaccount $sa \
          -n openedx \
          -p '{"imagePullSecrets": [{"name": "dockerhub-creds"}]}'
    fi
done

echo -e "\n${GREEN}✓${NC} Docker Hub credentials configured successfully!"
echo -e "You can now deploy Open edX with 'make deploy'"
