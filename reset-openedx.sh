#!/bin/bash

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${YELLOW}=== Complete Reset of Open edX on K3s ===${NC}"
echo -e "${RED}WARNING: This will delete ALL Open edX resources, including databases and persistent volumes!${NC}"
echo -e "All data will be lost and cannot be recovered."
echo -e "\nAre you sure you want to proceed? (yes/no): "
read confirmation

if [ "$confirmation" != "yes" ]; then
    echo -e "${YELLOW}Reset canceled.${NC}"
    exit 0
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Step 1: Delete all resources in the openedx namespace
echo -e "\n${YELLOW}Step 1: Deleting all resources in the openedx namespace${NC}"
if kubectl get namespace openedx &> /dev/null; then
    echo -e "Force deleting all resources in the openedx namespace..."
    
    # Force delete all pods first
    echo -e "Force deleting all pods..."
    kubectl delete pods --all -n openedx --force --grace-period=0
    echo -e "${GREEN}✓${NC} All pods force deleted"
    
    # Delete other resources
    echo -e "Deleting other resources..."
    kubectl delete all --all -n openedx
    echo -e "${GREEN}✓${NC} All resources deleted"
    
    # Delete PVCs
    echo -e "Deleting persistent volume claims..."
    kubectl delete pvc --all -n openedx --force --grace-period=0
    echo -e "${GREEN}✓${NC} All PVCs deleted"
    
    # Delete ConfigMaps
    echo -e "Deleting config maps..."
    kubectl delete configmap --all -n openedx --force --grace-period=0
    echo -e "${GREEN}✓${NC} All ConfigMaps deleted"
    
    # Delete Secrets
    echo -e "Deleting secrets..."
    kubectl delete secret --all -n openedx --force --grace-period=0
    echo -e "${GREEN}✓${NC} All Secrets deleted"
    
    # Wait a moment
    echo -e "Waiting for resources to be cleaned up..."
    sleep 3
    
    # Check for any remaining stuck pods
    STUCK_PODS=$(kubectl get pods -n openedx 2>/dev/null | grep -v "NAME" | awk '{print $1}')
    if [ ! -z "$STUCK_PODS" ]; then
        echo -e "${YELLOW}Some pods still exist. Force deleting them individually...${NC}"
        for pod in $STUCK_PODS; do
            echo -e "Force deleting pod: $pod"
            kubectl delete pod -n openedx $pod --force --grace-period=0
        done
    fi
    
    # Force delete the namespace itself
    echo -e "Force deleting the openedx namespace..."
    kubectl delete namespace openedx --force --grace-period=0
    echo -e "${GREEN}✓${NC} Namespace deleted"
else
    echo -e "${YELLOW}Namespace openedx does not exist. Nothing to delete.${NC}"
fi

# Step 2: Clean up Tutor configuration
echo -e "\n${YELLOW}Step 2: Cleaning up Tutor configuration${NC}"
echo -e "Would you like to reset Tutor configuration as well? (yes/no): "
read reset_tutor

if [ "$reset_tutor" = "yes" ]; then
    echo -e "Resetting Tutor configuration..."
    tutor config save --set LMS_HOST=local.overhang.io
    tutor config save --set CMS_HOST=studio.local.overhang.io
    echo -e "${GREEN}✓${NC} Tutor configuration reset to defaults"
else
    echo -e "${YELLOW}Keeping existing Tutor configuration.${NC}"
fi

echo -e "\n${GREEN}=== Reset Complete ===${NC}"
echo -e "You can now redeploy Open edX with 'make deploy'"
