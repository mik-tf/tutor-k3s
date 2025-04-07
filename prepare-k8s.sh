#!/bin/bash

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Preparing Kubernetes for Tutor ===${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Create the openedx namespace
echo -e "Creating openedx namespace..."
if kubectl get namespace openedx &> /dev/null; then
    echo -e "${YELLOW}Namespace openedx already exists${NC}"
else
    kubectl create namespace openedx
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Created namespace openedx"
    else
        echo -e "${RED}✗${NC} Failed to create namespace openedx"
        exit 1
    fi
fi

# Install required plugins for Tutor
echo -e "\n${YELLOW}Installing required Tutor plugins...${NC}"
pip install tutor-mfe tutor-indigo

# Check and increase file descriptor limits
echo -e "\n${YELLOW}Checking file descriptor limits...${NC}"
CURRENT_LIMIT=$(ulimit -n)
echo -e "Current file descriptor limit: $CURRENT_LIMIT"

if [ "$CURRENT_LIMIT" -lt 65535 ]; then
    echo -e "${YELLOW}Current limit is too low for OpenEdX container images.${NC}"
    echo -e "Attempting to increase file descriptor limits..."
    
    # Try to increase the limit for the current session
    ulimit -n 65535 2>/dev/null
    
    # Check if we were able to increase it
    NEW_LIMIT=$(ulimit -n)
    if [ "$NEW_LIMIT" -gt "$CURRENT_LIMIT" ]; then
        echo -e "${GREEN}✓${NC} Successfully increased file descriptor limit to $NEW_LIMIT for this session"
    else
        echo -e "${YELLOW}Could not increase limit for this session.${NC}"
        
        # Check if we have sudo access to modify system limits
        if command -v sudo &> /dev/null; then
            echo -e "${YELLOW}Attempting to add system-wide file descriptor limits...${NC}"
            echo -e "This will require sudo access and may prompt for your password."
            
            # Create a temporary file with the new limits
            TMP_FILE=$(mktemp)
            cat > "$TMP_FILE" << EOF
# Increase file descriptor limits for OpenEdX
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
            
            # Try to add the limits file
            sudo cp "$TMP_FILE" /etc/security/limits.d/99-openedx-limits.conf 2>/dev/null
            rm "$TMP_FILE"
            
            echo -e "${YELLOW}System-wide limits have been added.${NC}"
            echo -e "${YELLOW}You may need to log out and log back in for these changes to take effect.${NC}"
            echo -e "${YELLOW}Alternatively, restart your K3s service with: sudo systemctl restart k3s${NC}"
        else
            echo -e "${RED}Warning: File descriptor limits are too low for OpenEdX.${NC}"
            echo -e "You should manually increase the limits by adding the following to /etc/security/limits.conf:"
            echo -e "* soft nofile 65535"
            echo -e "* hard nofile 65535"
            echo -e "Then log out and log back in, or restart your K3s service."
        fi
    fi
else
    echo -e "${GREEN}✓${NC} File descriptor limits are sufficient"
fi

# Set up storage classes if needed
echo -e "\n${YELLOW}Checking storage classes...${NC}"
if ! kubectl get storageclass &> /dev/null; then
    echo -e "${RED}Warning: No storage classes found in the cluster${NC}"
    echo -e "Creating a default storage class using the local-path provisioner..."
    
    # Apply the local-path storage provisioner
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Local-path storage provisioner installed"
        # Make it the default storage class
        kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
        echo -e "${GREEN}✓${NC} Set local-path as the default storage class"
    else
        echo -e "${RED}✗${NC} Failed to install local-path storage provisioner"
        echo -e "You may need to manually set up a storage class for persistent volumes."
    fi
else
    echo -e "${GREEN}✓${NC} Storage classes exist in the cluster"
fi

# Check for ingress controller
echo -e "\n${YELLOW}Checking for ingress controller...${NC}"
if ! kubectl get pods -n kube-system -l app=ingress-nginx &> /dev/null; then
    echo -e "${YELLOW}No NGINX ingress controller found. Installing...${NC}"
    
    # Apply the NGINX ingress controller
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} NGINX ingress controller installed"
    else
        echo -e "${RED}✗${NC} Failed to install NGINX ingress controller"
        echo -e "You may need to manually set up an ingress controller."
    fi
else
    echo -e "${GREEN}✓${NC} Ingress controller exists in the cluster"
fi

echo -e "\n${GREEN}=== Kubernetes Preparation Complete ===${NC}"
echo -e "You can now run: tutor k8s init"
