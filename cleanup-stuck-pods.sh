#!/bin/bash

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Cleaning up stuck pods in openedx namespace ===${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace openedx &> /dev/null; then
    echo -e "${RED}Error: openedx namespace does not exist${NC}"
    exit 1
fi

# Force delete all pods in Terminating state
echo -e "Checking for stuck pods in Terminating state..."
STUCK_PODS=$(kubectl get pods -n openedx | grep Terminating | awk '{print $1}')

if [ -z "$STUCK_PODS" ]; then
    echo -e "${GREEN}No pods stuck in Terminating state found.${NC}"
else
    echo -e "${YELLOW}Found $(echo "$STUCK_PODS" | wc -l) pods stuck in Terminating state.${NC}"
    echo -e "Force deleting stuck pods..."
    
    for pod in $STUCK_PODS; do
        echo -e "Force deleting pod: $pod"
        kubectl delete pod -n openedx $pod --force --grace-period=0
    done
    
    echo -e "${GREEN}✓${NC} Forced deletion of stuck pods"
    
    # Verify all pods are gone
    sleep 3
    REMAINING=$(kubectl get pods -n openedx | grep Terminating | awk '{print $1}')
    if [ ! -z "$REMAINING" ]; then
        echo -e "${YELLOW}Some pods are still stuck. Trying one more time with kubectl patch...${NC}"
        for pod in $REMAINING; do
            echo -e "Patching finalizers for pod: $pod"
            kubectl patch pod $pod -n openedx -p '{"metadata":{"finalizers":null}}' --type=merge
            kubectl delete pod -n openedx $pod --force --grace-period=0
        done
    fi
fi

# Check for other problematic pods
echo -e "\nChecking for pods in other problematic states..."
PROBLEM_PODS=$(kubectl get pods -n openedx | grep -E 'ImagePullBackOff|ErrImagePull|CrashLoopBackOff' | awk '{print $1}')

if [ -z "$PROBLEM_PODS" ]; then
    echo -e "${GREEN}No pods in problematic states found.${NC}"
else
    echo -e "${YELLOW}Found pods with issues. Force deleting them...${NC}"
    for pod in $PROBLEM_PODS; do
        echo -e "Force deleting problematic pod: $pod"
        kubectl delete pod -n openedx $pod --force --grace-period=0
    done
    echo -e "${GREEN}✓${NC} Forced deletion of problematic pods"
fi

echo -e "\n${GREEN}=== Cleanup Complete ===${NC}"
echo -e "You can now continue with your deployment or run 'make reset' to start fresh."
