.PHONY: setup activate clean help prepare deploy registry-auth reset

# Default target
all: setup

# Set up the Tutor K3s environment
setup:
	@echo "Setting up Tutor K3s environment..."
	@chmod +x setup.sh
	@./setup.sh

# Activate the environment (detects shell type)
activate:
	@SHELL_TYPE=$$(ps -p $$$$ -o comm= | sed 's/-//g'); \
	if [ "$$SHELL_TYPE" = "fish" ]; then \
		echo "Detected fish shell. To activate the Tutor K3s environment, run:"; \
		echo "source ./activate.fish"; \
	else \
		echo "To activate the Tutor K3s environment, run:"; \
		echo "source ./activate.sh"; \
	fi

# Prepare Kubernetes for Tutor
prepare:
	@echo "Preparing Kubernetes for Tutor..."
	@chmod +x prepare-k8s.sh
	@./prepare-k8s.sh

# Configure Docker registry authentication
registry-auth:
	@echo "Configuring Docker registry authentication..."
	@chmod +x configure-registry-auth.sh
	@./configure-registry-auth.sh

# Deploy Open edX on Kubernetes
deploy: registry-auth
	@echo "Deploying Open edX on Kubernetes..."
	@chmod +x deploy-openedx.sh
	@./deploy-openedx.sh

# Complete reset of Open edX deployment
reset:
	@echo "Performing complete reset of Open edX deployment..."
	@chmod +x reset-openedx.sh
	@./reset-openedx.sh

# Clean up Python virtual environment and cached files
clean:
	@echo "Cleaning up Tutor K3s environment..."
	@rm -rf venv
	@find . -type d -name "__pycache__" -exec rm -rf {} +
	@find . -type f -name "*.pyc" -delete

# Help information
help:
	@echo "Tutor K3s Makefile Targets:"
	@echo "  make         - Run the default setup (same as 'make setup')"
	@echo "  make setup   - Set up the Tutor K3s environment"
	@echo "  make activate - Show instructions to activate the environment"
	@echo "  make prepare - Prepare Kubernetes cluster for Tutor (create namespace, etc.)"
	@echo "  make registry-auth - Configure Docker registry authentication for image pulls"
	@echo "  make deploy  - Deploy Open edX on the K3s cluster (includes registry-auth)"
	@echo "  make reset   - Completely reset the Open edX deployment (deletes all data)"
	@echo "  make clean   - Clean up Python virtual environment and cached files"
