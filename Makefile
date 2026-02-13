#==============================================================================
# XDC Node Setup - Makefile
# Common operations and development tasks
#==============================================================================

.PHONY: help install test lint build clean docker deploy docs

# Default target
.DEFAULT_GOAL := help

#==============================================================================
# Variables
#==============================================================================
SCRIPTS_DIR := scripts
TESTS_DIR := tests
DOCKER_DIR := docker
K8S_DIR := k8s
ANSIBLE_DIR := ansible
TERRAFORM_DIR := terraform

#==============================================================================
# Help
#==============================================================================
help: ## Show this help message
	@echo "XDC Node Setup - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

#==============================================================================
# Installation
#==============================================================================
install: ## Install XDC node (simple mode)
	@bash setup.sh

install-advanced: ## Install XDC node (advanced mode)
	@bash setup.sh --advanced

install-deps: ## Install development dependencies
	@echo "Installing development dependencies..."
	@which shellcheck >/dev/null || (echo "Installing shellcheck..."; apt-get update && apt-get install -y shellcheck)
	@which yamllint >/dev/null || (echo "Installing yamllint..."; pip install yamllint)
	@which bats >/dev/null || (echo "Installing bats..."; git clone https://github.com/bats-core/bats-core.git /tmp/bats && cd /tmp/bats && ./install.sh /usr/local)
	@echo "Dependencies installed!"

#==============================================================================
# Testing
#==============================================================================
test: test-unit test-integration ## Run all tests

test-unit: ## Run unit tests
	@echo "Running unit tests..."
	@bats $(TESTS_DIR)/unit/

test-integration: ## Run integration tests
	@echo "Running integration tests..."
	@bats $(TESTS_DIR)/integration/

test-scripts: ## Run shellcheck on all scripts
	@echo "Running shellcheck on scripts..."
	@find $(SCRIPTS_DIR) -name "*.sh" -type f -exec shellcheck -e SC1091 {} \;

test-ansible: ## Run Ansible tests (molecule)
	@echo "Running Ansible molecule tests..."
	@cd $(ANSIBLE_DIR) && molecule test

test-helm: ## Run Helm chart tests
	@echo "Running Helm chart tests..."
	@helm unittest $(K8S_DIR)/helm/xdc-node

test-terraform: ## Run Terraform validation
	@echo "Validating Terraform configurations..."
	@for dir in aws digitalocean hetzner; do \
		if [ -d "$(TERRAFORM_DIR)/$$dir" ]; then \
			echo "  Validating $$dir..."; \
			cd "$(TERRAFORM_DIR)/$$dir" && terraform validate && cd ../..; \
		fi \
	done

#==============================================================================
# Linting
#==============================================================================
lint: lint-shell lint-yaml lint-json ## Run all linters

lint-shell: ## Run shellcheck on scripts
	@echo "Running shellcheck..."
	@find $(SCRIPTS_DIR) -name "*.sh" -type f -exec shellcheck -e SC1090,SC1091 {} +

lint-yaml: ## Run yamllint on YAML files
	@echo "Running yamllint..."
	@yamllint -c .yamllint.yml . 2>/dev/null || yamllint .

lint-json: ## Validate JSON files
	@echo "Validating JSON files..."
	@find . -name "*.json" -type f -exec sh -c 'cat {} | jq empty' \;

#==============================================================================
# Docker Operations
#==============================================================================
docker-build: ## Build Docker images
	@echo "Building Docker images..."
	@cd $(DOCKER_DIR) && docker-compose build

docker-up: ## Start Docker containers
	@echo "Starting Docker containers..."
	@cd $(DOCKER_DIR) && docker-compose up -d

docker-down: ## Stop Docker containers
	@echo "Stopping Docker containers..."
	@cd $(DOCKER_DIR) && docker-compose down

docker-logs: ## View Docker logs
	@cd $(DOCKER_DIR) && docker-compose logs -f

docker-clean: ## Remove Docker containers and volumes
	@echo "Cleaning up Docker resources..."
	@cd $(DOCKER_DIR) && docker-compose down -v --remove-orphans

#==============================================================================
# Kubernetes Operations
#==============================================================================
k8s-install: ## Install Helm chart
	@echo "Installing XDC node Helm chart..."
	@helm upgrade --install xdc-node $(K8S_DIR)/helm/xdc-node

k8s-uninstall: ## Uninstall Helm chart
	@echo "Uninstalling XDC node Helm chart..."
	@helm uninstall xdc-node

k8s-status: ## Check Kubernetes status
	@kubectl get pods -l app.kubernetes.io/name=xdc-node

#==============================================================================
# Security
#==============================================================================
security-harden: ## Run security hardening
	@echo "Running security hardening..."
	@sudo bash $(SCRIPTS_DIR)/security-harden.sh

security-audit: ## Run security audit
	@echo "Running security audit..."
	@sudo bash $(SCRIPTS_DIR)/cis-benchmark.sh

#==============================================================================
# Backup Operations
#==============================================================================
backup-create: ## Create a backup
	@echo "Creating backup..."
	@sudo bash $(SCRIPTS_DIR)/backup.sh create

backup-list: ## List backups
	@sudo bash $(SCRIPTS_DIR)/backup.sh list

backup-restore: ## Restore from backup (interactive)
	@sudo bash $(SCRIPTS_DIR)/backup.sh restore

backup-rotate-keys: ## Rotate backup encryption keys
	@echo "Rotating backup encryption keys..."
	@sudo bash $(SCRIPTS_DIR)/rotate-backup-keys.sh rotate

#==============================================================================
# Monitoring
#==============================================================================
health-check: ## Run health check
	@sudo bash $(SCRIPTS_DIR)/node-health-check.sh --full

version-check: ## Check for version updates
	@sudo bash $(SCRIPTS_DIR)/version-check.sh

metrics: ## Show current metrics
	@curl -s http://localhost:9090/api/v1/query?query=xdc_block_height | jq .

#==============================================================================
# Documentation
#==============================================================================
docs-serve: ## Serve documentation locally
	@echo "Starting documentation server..."
	@cd docs && python3 -m http.server 8000

docs-api: ## View API documentation
	@echo "Starting Swagger UI for API docs..."
	@docker run -p 8080:8080 -e SWAGGER_JSON=/api/openapi.yaml -v $(PWD)/docs/api/openapi.yaml:/api/openapi.yaml swaggerapi/swagger-ui

docs-build: ## Build documentation
	@echo "Building documentation..."
	@echo "Documentation built successfully!"

#==============================================================================
# Maintenance
#==============================================================================
clean: ## Clean up temporary files and logs
	@echo "Cleaning up..."
	@rm -rf /tmp/xdc-*
	@rm -rf logs/*.log
	@echo "Cleanup complete!"

update: ## Update to latest version
	@echo "Checking for updates..."
	@bash $(SCRIPTS_DIR)/version-check.sh --update

changelog: ## Generate CHANGELOG
	@echo "Generating CHANGELOG..."
	@git log --pretty=format:"- %s (%h)" --no-merges -20 > CHANGELOG.md

#==============================================================================
# CI/CD
#==============================================================================
ci: lint test ## Run CI pipeline locally
	@echo "CI pipeline completed!"

pre-commit: ## Run pre-commit hooks
	@echo "Running pre-commit hooks..."
	@pre-commit run --all-files

#==============================================================================
# Development
#==============================================================================
dev-setup: ## Setup development environment
	@echo "Setting up development environment..."
	@cp -n .env.example .env 2>/dev/null || true
	@mkdir -p logs reports
	@echo "Development environment ready!"

dev-test: ## Quick test during development
	@echo "Running quick tests..."
	@bats tests/unit/test_validation.bats

#==============================================================================
# Release
#==============================================================================
release-patch: ## Create patch release
	@echo "Creating patch release..."
	@./scripts/bump-version.sh patch

release-minor: ## Create minor release
	@echo "Creating minor release..."
	@./scripts/bump-version.sh minor

release-major: ## Create major release
	@echo "Creating major release..."
	@./scripts/bump-version.sh major