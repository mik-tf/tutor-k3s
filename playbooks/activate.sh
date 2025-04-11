#!/bin/bash
# Activate the tutor-k3s-ansible environment

# Set KUBECONFIG
export KUBECONFIG="/home/pcone/Documents/temp/ws9/tutor-k3s/playbooks/../../tfgrid-k3s/k3s.yaml"

# Activate Python virtual environment
source "/home/pcone/Documents/temp/ws9/tutor-k3s/playbooks/venv/bin/activate"

echo "Tutor K3s environment activated."
echo "KUBECONFIG set to: ${KUBECONFIG}"
echo "Python virtual environment activated."
