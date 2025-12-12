.PHONY: lint lint-fix lint-ci setup check help validate validate-yaml

# Default: run linters
all: lint

##@ Linting

lint: ## Run all linters via pre-commit
	@pre-commit run --all-files

lint-ci: ## Run linters with diff output (for CI)
	@pre-commit run --all-files --show-diff-on-failure

##@ Validation

validate: ## Validate shell script syntax
	@echo "Validating shell scripts..."
	@bash -n install.sh
	@bash -n config/aliases.sh
	@echo "All scripts parse OK"

validate-yaml: ## Validate YAML file syntax
	@echo "Validating YAML syntax..."
	@python3 -c "import yaml; yaml.safe_load(open('bootstrap.yaml'))"
	@echo "YAML OK"

##@ Setup

setup: ## Install pre-commit hooks
	@echo "Installing pre-commit hooks..."
	@pre-commit install
	@pre-commit install --hook-type commit-msg
	@echo ""
	@echo "Setup complete. Run 'make lint' to verify."

check: ## Check required tools are installed
	@echo "Checking tools..."
	@printf "pre-commit:   "; command -v pre-commit >/dev/null && echo "OK" || echo "MISSING - uv tool install pre-commit"
	@printf "shellcheck:   "; command -v shellcheck >/dev/null && echo "OK" || echo "MISSING"
	@printf "yamllint:     "; command -v yamllint >/dev/null && echo "OK" || echo "MISSING"

##@ Utility

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; ORS="";} \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0,5); next } \
		/^[a-zA-Z0-9_.-]+:.*##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
		END { if (NR==0) print "No help available.\n" }' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help
