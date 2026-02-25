# vLLM · Fastify · Nginx - Makefile
.PHONY: help setup build start start-local start-runpod stop restart status logs test test-local clean update build-runpod push-runpod release-runpod

# Default target
help: ## Show this help message
	@echo "vLLM · Fastify · Nginx — Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""

setup: ## One-time setup: generate nginx config, htpasswd, secrets
	@echo "⦿ Setting up vLLM, Fastify, Nginx..."
	@chmod +x scripts/*.sh scripts/runpod/*.sh scripts/test/*.sh
	@./scripts/setup.sh

build: ## Build/rebuild the Fastify proxy image (local compose)
	@echo "⦿ Building containers..."
	@docker compose build

start: ## Start local stack (base compose, SSL on 8443)
	@echo "⦿ Starting services..."
	@./scripts/start.sh

start-local: ## Start local stack against a host-side backend (HTTP on 8080)
	@echo "⦿ Starting local stack (nginx→fastify→host backend)..."
	@docker compose -f docker-compose.yml -f docker-compose.local.yml up --build -d

start-runpod: ## Start RunPod stack locally with vLLM container (HTTP on 8080)
	@echo "⦿ Starting RunPod stack locally..."
	@docker compose -f docker-compose.yml -f docker-compose.runpod.yml up --build -d

stop: ## Stop all services
	@echo "⦿ Stopping services..."
	@./scripts/stop.sh

restart: ## Restart all services
	@echo "⦿ Restarting services..."
	@$(MAKE) stop
	@$(MAKE) start

status: ## Check service status
	@./scripts/status.sh

logs: ## Tail logs from all services
	@echo "⦿ Viewing logs..."
	@docker compose logs -f --timestamps

test: ## Run API smoke tests
	@echo "⦿ Testing API..."
	@./scripts/test/test.sh

test-local: ## E2E test the local/RunPod stack (HTTP port 8080)
	@echo "⦿ Running E2E tests against http://localhost:8080..."
	@./scripts/test/test-local.sh

clean: ## Remove containers, volumes and prune Docker system
	@echo "⦿ Cleaning up..."
	@docker compose down -v
	@docker system prune -f

update: ## git pull, rebuild, and restart
	@echo "⦿ Updating services..."
	@git pull
	@$(MAKE) build
	@$(MAKE) restart

# ── RunPod ────────────────────────────────────────────────────────────────────
RUNPOD_IMAGE ?= $(shell grep '^RUNPOD_IMAGE' .env 2>/dev/null | cut -d= -f2 | tr -d '"')

build-runpod: ## Build the RunPod single-container image (linux/amd64)
	@echo "⦿ Building RunPod image: $(RUNPOD_IMAGE)"
	@docker build --platform linux/amd64 -f Dockerfile.runpod -t $(RUNPOD_IMAGE) .

push-runpod: ## Push the RunPod image to Docker Hub / GHCR
	@echo "⦿ Pushing $(RUNPOD_IMAGE)..."
	@docker push $(RUNPOD_IMAGE)

release-runpod: build-runpod push-runpod ## Build + push in one step
