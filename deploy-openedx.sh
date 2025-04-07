#!/bin/bash

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${YELLOW}=== Open edX Deployment on K3s ===${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if tutor is available
if ! command -v tutor &> /dev/null; then
    echo -e "${RED}Error: tutor is not installed or not in PATH${NC}"
    exit 1
fi

# Step 1: Ensure the environment is activated
echo -e "\n${YELLOW}Step 1: Ensuring environment is activated${NC}"
if [ -z "$KUBECONFIG" ]; then
    echo -e "${RED}Error: KUBECONFIG is not set. Please activate the environment first:${NC}"
    echo -e "source ${SCRIPT_DIR}/activate.fish  # For fish shell"
    echo -e "source ${SCRIPT_DIR}/activate.sh    # For bash shell"
    exit 1
else
    echo -e "${GREEN}✓${NC} KUBECONFIG is set to: $KUBECONFIG"
fi

# Step 1.5: Check file descriptor limits
echo -e "\n${YELLOW}Step 1.5: Checking file descriptor limits${NC}"
CURRENT_LIMIT=$(ulimit -n)
echo -e "Current file descriptor limit: $CURRENT_LIMIT"

if [ "$CURRENT_LIMIT" -lt 65535 ]; then
    echo -e "${RED}Warning: File descriptor limit is too low (${CURRENT_LIMIT}).${NC}"
    echo -e "OpenEdX container images require higher limits to prevent 'too many open files' errors."
    echo -e "Attempting to increase limit for this session..."
    
    # Try to increase the limit for the current session
    ulimit -n 65535 2>/dev/null
    NEW_LIMIT=$(ulimit -n)
    
    if [ "$NEW_LIMIT" -gt "$CURRENT_LIMIT" ]; then
        echo -e "${GREEN}✓${NC} Successfully increased file descriptor limit to $NEW_LIMIT for this session"
    else
        echo -e "${YELLOW}Could not increase limit for this session.${NC}"
        echo -e "${YELLOW}You may encounter 'ImagePullBackOff' errors with 'too many open files' messages.${NC}"
        echo -e "${YELLOW}To fix this permanently, run the prepare-k8s.sh script or manually increase system limits.${NC}"
        
        echo -e "\nDo you want to continue anyway? (y/n)"
        read -r CONTINUE_DEPLOY
        if [[ ! "$CONTINUE_DEPLOY" =~ ^[Yy]$ ]]; then
            echo -e "Deployment aborted. Please run ${SCRIPT_DIR}/prepare-k8s.sh to fix the file descriptor limits."
            exit 1
        fi
        echo -e "Continuing with deployment despite low file descriptor limits..."
    fi
else
    echo -e "${GREEN}✓${NC} File descriptor limits are sufficient ($CURRENT_LIMIT)"
fi

# Step 2: Clean up any existing failed deployment
echo -e "\n${YELLOW}Step 2: Cleaning up any existing failed deployment${NC}"
echo -e "Deleting jobs, configmaps, and other resources that might conflict..."
kubectl delete -n openedx --all jobs,configmaps 2>/dev/null || true
echo -e "${GREEN}✓${NC} Cleanup completed"

# Step 3: Create the openedx namespace if it doesn't exist
echo -e "\n${YELLOW}Step 3: Ensuring openedx namespace exists${NC}"
if kubectl get namespace openedx &> /dev/null; then
    echo -e "${GREEN}✓${NC} Namespace openedx already exists"
else
    kubectl create namespace openedx
    echo -e "${GREEN}✓${NC} Created namespace openedx"
fi

# Step 4: Install required plugins
echo -e "\n${YELLOW}Step 4: Installing required Tutor plugins${NC}"
if ! tutor plugins list | grep -q "indigo.*enabled"; then
    echo -e "Installing and enabling indigo plugin..."
    pip install tutor-indigo
    tutor plugins enable indigo
    echo -e "${GREEN}✓${NC} Indigo plugin installed and enabled"
else
    echo -e "${GREEN}✓${NC} Indigo plugin is already enabled"
fi

if ! tutor plugins list | grep -q "mfe.*enabled"; then
    echo -e "Installing and enabling mfe plugin..."
    pip install tutor-mfe
    tutor plugins enable mfe
    echo -e "${GREEN}✓${NC} MFE plugin installed and enabled"
else
    echo -e "${GREEN}✓${NC} MFE plugin is already enabled"
fi

# Step 5: Verify Docker registry authentication
echo -e "\n${YELLOW}Step 5: Verifying Docker registry authentication${NC}"
if kubectl get secret -n openedx dockerhub-creds &>/dev/null; then
    echo -e "${GREEN}✓${NC} Docker registry authentication is configured"
else
    echo -e "${YELLOW}Docker registry authentication not found.${NC}"
    echo -e "Running registry authentication setup..."
    ${SCRIPT_DIR}/configure-registry-auth.sh
fi

# Step 6: Configure Tutor with proper hostnames
echo -e "\n${YELLOW}Step 6: Configuring Tutor with proper hostnames${NC}"
echo -e "Setting LMS_HOST to lms.local..."
tutor config save --set LMS_HOST=lms.local
echo -e "Setting CMS_HOST to studio.local..."
tutor config save --set CMS_HOST=studio.local
echo -e "${GREEN}✓${NC} Tutor configuration updated"

# Step 7: Save the configuration
echo -e "\n${YELLOW}Step 7: Saving Tutor configuration${NC}"
tutor config save
echo -e "${GREEN}✓${NC} Configuration saved"

# Step 8: Deploy Open edX on Kubernetes
echo -e "\n${YELLOW}Step 8: Deploying Open edX on Kubernetes${NC}"
tutor k8s start
echo -e "${GREEN}✓${NC} Deployment started"

# Step 9: Wait for pods to be ready
echo -e "\n${YELLOW}Step 9: Waiting for pods to be ready${NC}"
echo -e "This may take several minutes as images are pulled and containers are started..."
echo -e "Checking pod status every 10 seconds (press Ctrl+C to stop waiting)..."

MAX_RETRIES=30
RETRY_COUNT=0
ALL_READY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$ALL_READY" = false ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -e "\nAttempt $RETRY_COUNT of $MAX_RETRIES:"
    
    # Get pod status
    kubectl get pods -n openedx
    
    # Check for ImagePullBackOff issues
    IMAGE_PULL_ISSUES=$(kubectl get pods -n openedx -o json | jq -r '.items[] | select(.status.phase != "Running" and .status.containerStatuses[0].state.waiting.reason == "ImagePullBackOff") | .metadata.name')
    
    if [ ! -z "$IMAGE_PULL_ISSUES" ]; then
        echo -e "\n${YELLOW}Detected ImagePullBackOff issues. Attempting to fix...${NC}"
        for pod in $IMAGE_PULL_ISSUES; do
            echo -e "Deleting pod $pod to trigger a retry..."
            kubectl delete pod -n openedx $pod
        done
        echo -e "Waiting 20 seconds for new pods to be created..."
        sleep 20
    fi
    
    # Check for stuck Terminating pods
    STUCK_PODS=$(kubectl get pods -n openedx | grep Terminating | awk '{print $1}')
    if [ ! -z "$STUCK_PODS" ]; then
        echo -e "\n${YELLOW}Detected pods stuck in Terminating state. Force deleting them...${NC}"
        for pod in $STUCK_PODS; do
            echo -e "Force deleting pod: $pod"
            kubectl delete pod -n openedx $pod --force --grace-period=0
        done
        echo -e "Waiting 5 seconds for cleanup..."
        sleep 5
    fi
    
    # Check if all pods are ready
    NOT_READY=$(kubectl get pods -n openedx -o json | jq -r '.items[] | select(.status.phase != "Running" or ([ .status.containerStatuses[] | select(.ready == false) ] | length > 0)) | .metadata.name')
    
    if [ -z "$NOT_READY" ]; then
        ALL_READY=true
        echo -e "\n${GREEN}✓${NC} All pods are running and ready!"
        break
    else
        echo -e "\n${YELLOW}Some pods are not ready yet. Waiting 10 seconds...${NC}"
        sleep 10
    fi
done

if [ "$ALL_READY" = false ]; then
    echo -e "\n${YELLOW}Warning: Not all pods are ready after $MAX_RETRIES attempts.${NC}"
    
    # Check for persistent ImagePullBackOff issues
    PERSISTENT_ISSUES=$(kubectl get pods -n openedx -o json | jq -r '.items[] | select(.status.phase != "Running" and .status.containerStatuses[0].state.waiting.reason == "ImagePullBackOff") | .metadata.name')
    
    if [ ! -z "$PERSISTENT_ISSUES" ]; then
        echo -e "${RED}There are persistent image pull issues with the following pods:${NC}"
        for pod in $PERSISTENT_ISSUES; do
            echo -e "- $pod"
        done
        echo -e "\n${YELLOW}Possible solutions:${NC}"
        echo -e "1. Check if your nodes have internet access to pull Docker images"
        echo -e "2. Check if you're hitting Docker Hub rate limits"
        echo -e "3. Try manually pulling the images on your nodes"
        echo -e "4. Consider using a private registry or image pull secrets"
    fi
    
    echo -e "\nYou can continue with initialization, but some services might not be available yet."
    echo -e "To check pod status manually, run: kubectl get pods -n openedx"
fi

# Step 10: Initialize Open edX
echo -e "\n${YELLOW}Step 10: Initializing Open edX${NC}"
echo -e "This step creates the database schema and sets up the platform..."
tutor k8s init || true  # Continue even if there are non-fatal errors

# Step 11: Print access information
echo -e "\n${YELLOW}Step 11: Deployment Information${NC}"
echo -e "To access your Open edX instance, you need to add the following entries to your /etc/hosts file:"
echo -e "127.0.0.1 lms.local studio.local"
echo -e "\nTo create a superuser account, run:"
echo -e "tutor k8s exec lms -- python manage.py lms createsuperuser"
echo -e "\nTo check the status of your deployment:"
echo -e "tutor k8s status"
echo -e "\nTo port-forward the LMS service to access it locally:"
echo -e "kubectl port-forward -n openedx svc/lms 8000:8000"
echo -e "Then access: http://lms.local:8000"
echo -e "\nTo port-forward the Studio service to access it locally:"
echo -e "kubectl port-forward -n openedx svc/cms 8001:8000"
echo -e "Then access: http://studio.local:8001"

echo -e "\n${GREEN}=== Open edX Deployment Complete ===${NC}"
