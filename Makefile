.PHONY: help setup prepare registry-auth deploy cleanup reset

help: ## Show this help
	@echo "Tutor K3s Ansible - Open edX on K3s using Ansible"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Set up the environment (KUBECONFIG, Python venv, tutor)
	KUBECONFIG=$(CURDIR)/../tfgrid-k3s/k3s.yaml ansible-playbook playbooks/setup.yml

prepare: ## Prepare Kubernetes for Tutor (namespace, plugins, storage, ingress)
	KUBECONFIG=$(CURDIR)/../tfgrid-k3s/k3s.yaml ansible-playbook playbooks/prepare.yml

registry-auth: ## Configure Docker registry authentication
	KUBECONFIG=$(CURDIR)/../tfgrid-k3s/k3s.yaml ansible-playbook playbooks/registry-auth.yml

deploy: ## Deploy Open edX on Kubernetes
	KUBECONFIG=$(CURDIR)/../tfgrid-k3s/k3s.yaml ansible-playbook playbooks/deploy.yml

cleanup: ## Clean up stuck pods
	KUBECONFIG=$(CURDIR)/../tfgrid-k3s/k3s.yaml ansible-playbook playbooks/cleanup.yml

reset: ## Reset the Open edX deployment
	KUBECONFIG=$(CURDIR)/../tfgrid-k3s/k3s.yaml ansible-playbook playbooks/reset.yml

all: setup prepare registry-auth deploy ## Run all steps in sequence
