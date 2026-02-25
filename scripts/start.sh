#!/bin/bash

set -e

echo "⦿ Starting Fastify proxy, Nginx services..."

if [ -f .env ]; then
    source .env
else
    echo ".env file not found. Please run ./setup.sh first."
    exit 1
fi

echo "⦿ Verifying backend API access..."
HOST_FOR_CHECK=${VLLM_HOST:-localhost}
if curl -s "http://${HOST_FOR_CHECK}:${VLLM_PORT}/v1/models" > /dev/null 2>&1; then
    echo "Backend API is accessible at ${HOST_FOR_CHECK}:${VLLM_PORT}"
else
    echo "Cannot access backend API at ${HOST_FOR_CHECK}:${VLLM_PORT}"
    echo "   Make sure your backend (vLLM, Ollama, llama.cpp, etc.) is running and VLLM_HOST/VLLM_PORT are correct."
    exit 1
fi

echo "⦿ Starting Docker services..."
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d
else
    docker compose up -d
fi

echo "All services started successfully!"
echo ""
echo "Service URLs:"
echo "   - Local nginx: http://localhost:${NGINX_PORT:-8080}"
echo "   - Health check: http://localhost:${NGINX_PORT:-8080}/health"
echo ""
echo "Authentication:"
echo "   - Username: ${NGINX_BASIC_AUTH_USERNAME:-admin}"
echo "   - Password: $NGINX_BASIC_AUTH_PASSWORD"
echo ""
echo "Test the API:"
echo "   curl -u ${NGINX_BASIC_AUTH_USERNAME:-admin}:\$NGINX_BASIC_AUTH_PASSWORD http://localhost:${NGINX_PORT:-8080}/v1/models"
echo ""
echo "Monitor logs:"
echo "   docker compose logs -f"
