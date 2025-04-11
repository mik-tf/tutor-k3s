.PHONY: help setup prepare registry-auth deploy cleanup reset copy-k3s-config system

help: ## Show this help
	@echo "Tutor K3s Ansible - Open edX on K3s using Ansible"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

copy-k3s-config: ## Copy k3s config to local directory
	mkdir -p config
	cp ../tfgrid-k3s/k3s.yaml config/k3s.yaml

system: copy-k3s-config ## Run the system role playbook
	KUBECONFIG=config/k3s.yaml ansible-playbook roles/system/tasks/main.yml

setup: copy-k3s-config ## Set up the environment (KUBECONFIG, Python venv, tutor)
	KUBECONFIG=$(CURDIR)/config/k3s.yaml ansible-playbook playbooks/setup.yml

prepare: copy-k3s-config ## Prepare Kubernetes for Tutor (namespace, plugins, storage, ingress)
	KUBECONFIG=$(CURDIR)/config/k3s.yaml ansible-playbook playbooks/prepare.yml

registry-auth: copy-k3s-config ## Configure Docker registry authentication
	KUBECONFIG=$(CURDIR)/config/k3s.yaml ansible-playbook playbooks/registry-auth.yml

deploy: copy-k3s-config ## Deploy Open edX on Kubernetes
	KUBECONFIG=$(CURDIR)/config/k3s.yaml ansible-playbook playbooks/deploy.yml

cleanup: copy-k3s-config ## Clean up stuck pods
	KUBECONFIG=$(CURDIR)/config/k3s.yaml ansible-playbook playbooks/cleanup.yml

reset: copy-k3s-config ## Reset the Open edX deployment
	KUBECONFIG=$(CURDIR)/config/k3s.yaml ansible-playbook playbooks/reset.yml

all: copy-k3s-config setup prepare registry-auth deploy ## Run all steps in sequence
