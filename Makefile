# vLLM · Fastify · Nginx - Makefile
.PHONY: help setup build start stop restart status logs test clean update

# Default target
help: ## Show this help message
	@echo "vLLM · Fastify · Nginx — Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

setup: ## Setup the environment and dependencies
	@echo "⦿ Setting up vLLM, Fastify, Nginx..."
	@chmod +x scripts/*.sh
	@./scripts/setup.sh

build: ## Build/rebuild containers
	@echo "⦿ Building containers..."
	@docker-compose build --no-cache

start: ## Start all services
	@echo "⦿ Starting services..."
	@./scripts/start.sh

stop: ## Stop all services
	@echo "⦿ Stopping services..."
	@./scripts/stop.sh

restart: ## Restart all services
	@echo "⦿ Restarting services..."
	@$(MAKE) stop
	@$(MAKE) start

status: ## Check service status
	@./scripts/status.sh

logs: ## View service logs
	@echo "⦿ Viewing logs..."
	@docker-compose logs -f --timestamps

test: ## Test the API endpoints
	@echo "⦿ Testing API..."
	@./scripts/test/test.sh

test-local: ## E2E test the local/RunPod stack (HTTP port 8080)
	@echo "⦿ Running E2E tests against http://localhost:8080..."
	@./scripts/test/test-local.sh

clean: ## Clean up containers and volumes
	@echo "⦿ Cleaning up..."
	@docker-compose down -v
	@docker system prune -f

update: ## Update and restart services
	@echo "⦿ Updating services..."
	@git pull
	@$(MAKE) build
	@$(MAKE) restart

# ── RunPod ────────────────────────────────────────────────────────────────────
RUNPOD_IMAGE ?= $(shell grep '^RUNPOD_IMAGE' .env 2>/dev/null | cut -d= -f2)

build-runpod: ## Build the RunPod single-container image (linux/amd64)
	@echo "⦿ Building RunPod image: $(RUNPOD_IMAGE)"
	@docker build --platform linux/amd64 -f Dockerfile.runpod -t $(RUNPOD_IMAGE) .

push-runpod: ## Push the RunPod image to Docker Hub / GHCR
	@echo "⦿ Pushing $(RUNPOD_IMAGE)..."
	@docker push $(RUNPOD_IMAGE)

release-runpod: build-runpod push-runpod ## Build + push in one step

