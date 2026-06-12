REPO_ROOT := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

kind-up kind-down: export CLUSTER_NAME = odg-local
kind-up kind-update: export KUBECONFIG = $(REPO_ROOT)/local-setup/kind/kubeconfig
kind-up kind-update: export PATH_CLUSTER_CHART = $(REPO_ROOT)/local-setup/kind/cluster

kind-up: $(KIND) $(KUBECTL) $(HELM) $(OCM) ## Start local KinD cluster with ODG
	./local-setup/kind/kind-up.sh \
		--cluster-name $(CLUSTER_NAME) \
		--path-cluster-chart $(PATH_CLUSTER_CHART)
kind-update: $(KIND) $(KUBECTL) $(HELM) $(OCM) ## Update existing KinD cluster with latest changes
	./local-setup/kind/kind-update.sh \
		--path-cluster-chart $(PATH_CLUSTER_CHART)
kind-down: $(KIND) ## Tear down local KinD cluster
	./local-setup/kind/kind-down.sh \
		--cluster-name $(CLUSTER_NAME)

.PHONY: kind-up kind-update kind-down website-build website-setup website-dev website-serve website-clean help

# Default target
.DEFAULT_GOAL := help

# Build website documentation
website-build: ## Build the website using Sphinx
	sphinx-build -Eav docs/website website-out

# Setup website dependencies
website-setup: ## Install website dependencies
	pip3 install --break-system-packages -r docs/website/requirements.txt
	@echo "Adding ~/.local/bin to PATH (export PATH=~/.local/bin:\$$PATH)"

# Development mode with auto-rebuild and live server
website-dev: website-setup ## Setup and run website development server with auto-rebuild
	export PATH=$$HOME/.local/bin:$$PATH && sphinx-autobuild -Eav docs/website website-out

# Serve built website with Python HTTP server
website-serve: ## Serve the built website on http://localhost:8000
	@if [ ! -d "website-out" ]; then \
		echo "Error: website-out directory not found. Run 'make website-build' first."; \
		exit 1; \
	fi
	@echo "Serving website at http://localhost:8000"
	@echo "Press Ctrl+C to stop the server"
	cd website-out && python3 -m http.server 8000

# Clean website build artifacts
website-clean: ## Remove website build artifacts
	rm -rf website-out

# Help target
help: ## Show this help message
	@echo "Available targets:"
	@echo ""
	@echo "KinD (Local Development):"
	@grep -E '^kind-[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Website:"
	@grep -E '^website-[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
