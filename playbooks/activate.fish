# Fish shell script for activating the tutor-k3s-ansible environment

# Set KUBECONFIG
set -x KUBECONFIG "/home/pcone/Documents/temp/ws11/tutor-k3s-ansible/playbooks/../../tfgrid-k3s/k3s.yaml"

# Activate Python virtual environment
if test -f "/home/pcone/Documents/temp/ws11/tutor-k3s-ansible/playbooks/venv/bin/activate.fish"
    source "/home/pcone/Documents/temp/ws11/tutor-k3s-ansible/playbooks/venv/bin/activate.fish"
else
    echo "Warning: Virtual environment activation file not found"
end

echo "Tutor K3s environment activated."
echo "KUBECONFIG set to: $KUBECONFIG"
echo "Python virtual environment activated."
