# LM Studio Nginx Ngrok - Makefile
.PHONY: help setup build start stop restart status logs test clean update

# Default target
help: ## Show this help message
	@echo "LM Studio, Fastify, Nginx, Ngrok - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

setup: ## Setup the environment and dependencies
	@echo "⦿ Setting up LM Studio, Fastify, Nginx, Ngrok..."
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
	@docker-compose logs -f

test: ## Test the API endpoints
	@echo "⦿ Testing API..."
	@./scripts/test-api.sh

clean: ## Clean up containers and volumes
	@echo "⦿ Cleaning up..."
	@docker-compose down -v
	@docker system prune -f

update: ## Update and restart services
	@echo "⦿ Updating services..."
	@git pull
	@$(MAKE) build
	@$(MAKE) restart

