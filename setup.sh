#!/bin/bash

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TFGRID_DIR="$(cd "${SCRIPT_DIR}/../tfgrid-k3s" && pwd)"

echo -e "${YELLOW}=== Tutor K3s Setup ===${NC}"
echo -e "Setting up Tutor for K3s cluster deployed with tfgrid-k3s"

# Check if the k3s.yaml exists in the tfgrid-k3s directory
if [ ! -f "${TFGRID_DIR}/k3s.yaml" ]; then
    echo -e "${RED}Error: k3s.yaml not found in ${TFGRID_DIR}${NC}"
    echo -e "Please make sure you have deployed a K3s cluster using tfgrid-k3s first."
    exit 1
fi

# Set up KUBECONFIG to point to the k3s.yaml in the tfgrid-k3s directory
export KUBECONFIG="${TFGRID_DIR}/k3s.yaml"
echo -e "${GREEN}✓${NC} KUBECONFIG set to: ${KUBECONFIG}"

# Test kubectl connection
echo -e "\n${YELLOW}Testing kubectl connection...${NC}"
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓${NC} Successfully connected to Kubernetes cluster"
    echo -e "Cluster info:"
    kubectl cluster-info
    echo -e "\nNodes in the cluster:"
    kubectl get nodes -o wide
else
    echo -e "${RED}✗${NC} Failed to connect to Kubernetes cluster"
    echo -e "Please check your cluster status and credentials."
    exit 1
fi

# Set up Python virtual environment
echo -e "\n${YELLOW}Setting up Python virtual environment...${NC}"
if [ ! -d "${SCRIPT_DIR}/venv" ]; then
    echo "Creating new Python virtual environment..."
    python3 -m venv "${SCRIPT_DIR}/venv"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create Python virtual environment${NC}"
        echo -e "Please make sure python3-venv is installed."
        exit 1
    fi
else
    echo "Using existing Python virtual environment."
fi

# Activate the virtual environment
source "${SCRIPT_DIR}/venv/bin/activate"
echo -e "${GREEN}✓${NC} Python virtual environment activated"

# Install/upgrade pip
echo -e "\n${YELLOW}Upgrading pip...${NC}"
pip install --upgrade pip
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to upgrade pip${NC}"
    exit 1
fi

# Install tutor
echo -e "\n${YELLOW}Installing tutor...${NC}"
pip install tutor
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to install tutor${NC}"
    exit 1
fi

echo -e "\n${GREEN}=== Setup Complete ===${NC}"
echo -e "You can now use tutor with your K3s cluster."

# Create a bash activation script for future use
cat > "${SCRIPT_DIR}/activate.sh" << EOF
#!/bin/bash
# Activate the tutor-k3s environment

# Set KUBECONFIG
export KUBECONFIG="${TFGRID_DIR}/k3s.yaml"

# Activate Python virtual environment
source "${SCRIPT_DIR}/venv/bin/activate"

echo "Tutor K3s environment activated."
echo "KUBECONFIG set to: ${KUBECONFIG}"
echo "Python virtual environment activated."
EOF

chmod +x "${SCRIPT_DIR}/activate.sh"

# Create a fish activation script for future use
cat > "${SCRIPT_DIR}/activate.fish" << 'EOF'
# Fish shell script for activating the tutor-k3s environment

# Set KUBECONFIG
set -x KUBECONFIG "${TFGRID_DIR}/k3s.yaml"

# Activate Python virtual environment
if test -f "${SCRIPT_DIR}/venv/bin/activate.fish"
    source "${SCRIPT_DIR}/venv/bin/activate.fish"
else
    echo "Warning: Virtual environment activation file not found"
end

echo "Tutor K3s environment activated."
echo "KUBECONFIG set to: $KUBECONFIG"
echo "Python virtual environment activated."
EOF

# Replace variables in the fish script
sed -i "s|\${TFGRID_DIR}|${TFGRID_DIR}|g" "${SCRIPT_DIR}/activate.fish"
sed -i "s|\${SCRIPT_DIR}|${SCRIPT_DIR}|g" "${SCRIPT_DIR}/activate.fish"

echo -e "\nTo use this environment in the future, run:"
echo -e "${YELLOW}source ${SCRIPT_DIR}/activate.fish${NC}"
