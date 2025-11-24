#!/bin/bash

set -e

echo "⦿ Starting LM Studio, Fastify proxy, Nginx, Ngrok services..."

if [ -f .env ]; then
    source .env
else
    echo ".env file not found. Please run ./setup.sh first."
    exit 1
fi

echo "⦿ Checking LM Studio CLI..."
if ! command -v lms >/dev/null 2>&1; then
    echo "LM Studio CLI (lms) not found"
    echo "   Please install LM Studio from: https://lmstudio.ai/"
    exit 1
fi

echo "⦿ Checking LM Studio server status..."
LMS_STATUS=$(lms server status 2>/dev/null || echo "Server not running")
if [[ "$LMS_STATUS" == *"Server not running"* ]] || [[ "$LMS_STATUS" == *"error"* ]]; then
    echo "LM Studio server is not running"
    echo "   Please start the LM Studio server:"
    echo "   1. Open LM Studio application"
    echo "   2. Go to the 'Local Server' tab"
    echo "   3. Click 'Start Server' to enable the API"
    echo "   Or use CLI: lms server start"
    exit 1
else
    echo "LM Studio server is running"
fi

echo "⦿ Checking available models..."
AVAILABLE_MODELS=$(lms ls 2>/dev/null || echo "error")
if [[ "$AVAILABLE_MODELS" == *"error"* ]]; then
    echo "Could not list available models"
    echo "   Continuing with service startup..."
else
    if echo "$AVAILABLE_MODELS" | grep -q "$LMSTUDIO_MODEL"; then
        echo "Model $LMSTUDIO_MODEL is available"
    else
        echo "Model $LMSTUDIO_MODEL not found in downloaded models"
        echo "   You can download it with: lms get $LMSTUDIO_MODEL"
        echo "   Continuing with service startup..."
    fi
fi

echo "⦿ Verifying HTTP API access..."
HOST_FOR_CHECK=${LMSTUDIO_HOST:-localhost}
if curl -s "http://${HOST_FOR_CHECK}:${LMSTUDIO_PORT}/v1/models" > /dev/null 2>&1; then
    echo "LM Studio API is accessible at ${HOST_FOR_CHECK}:${LMSTUDIO_PORT}"
else
    echo "Cannot access LM Studio API at ${LMSTUDIO_HOST}:${LMSTUDIO_PORT}"
    echo "   Please start LM Studio server first:"
    echo "   1. Open LM Studio application"
    echo "   2. Go to Local Server tab"
    echo "   3. Click 'Start Server'"
    echo "   Or use CLI: lms server start"
    exit 1
fi

echo "⦿ Starting Docker services..."
if [ "$VLLM_BRIDGE_ENABLED" = "true" ]; then
    echo "VLLM Bridge enabled - starting with bridge service"
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose --profile vllm up -d
    else
        docker compose --profile vllm up -d
    fi
else
    echo "VLLM Bridge disabled - starting without bridge service"
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose up -d
    else
        docker compose up -d
    fi
fi

echo "All services started successfully!"
echo ""
echo "Note: LM Studio server must be started manually before using the API."
echo "   Start it with: lms server start"
echo "   Or open LM Studio app and go to Local Server tab"
echo ""

echo "Waiting for ngrok tunnel to establish..."
sleep 5
NGROK_URL=""
for i in {1..10}; do
    NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o 'https://[^"]*\.ngrok-free\.app' | head -1)
    if [ -n "$NGROK_URL" ]; then
        break
    fi
    sleep 1
done

echo "Service URLs:"
echo "   - Local nginx: http://localhost:$NGINX_PORT"
if [ "$SSL_ENABLED" = "true" ]; then
    echo "   - Local nginx (SSL): https://localhost:$NGINX_SSL_PORT"
fi
if [ "$VLLM_BRIDGE_ENABLED" = "true" ]; then
    echo "   - VLLM Bridge: http://localhost:$VLLM_BRIDGE_PORT"
    echo "   - VLLM Chat API: http://localhost:$VLLM_BRIDGE_PORT/v1/chat/completions"
fi
echo "   - Ngrok dashboard: http://localhost:4040"
if [ -n "$NGROK_URL" ]; then
    echo "   - Ngrok public URL: $NGROK_URL"
else
    echo "   - Ngrok public URL: Could not retrieve (check ngrok dashboard)"
fi
echo "   - Health check: http://localhost:$NGINX_PORT/health"
echo ""
echo "Authentication:"
echo "   - Username: $AUTH_USERNAME"
echo "   - Password: $AUTH_PASSWORD"
echo ""
echo "Test the API:"
if [ "$VLLM_BRIDGE_ENABLED" = "true" ]; then
    echo "   # LM Studio direct:"
    echo "   curl -u $AUTH_USERNAME:$AUTH_PASSWORD http://localhost:$NGINX_PORT/api/tags"
    echo "   # VLLM compatible:"
    echo "   curl -X POST http://localhost:$VLLM_BRIDGE_PORT/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"$LMSTUDIO_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
else
    echo "   curl -u $AUTH_USERNAME:$AUTH_PASSWORD http://localhost:$NGINX_PORT/api/tags"
fi
echo ""
echo "Monitor logs:"
if [ "$VLLM_BRIDGE_ENABLED" = "true" ]; then
    echo "   docker-compose --profile vllm logs -f"
else
    echo "   docker-compose logs -f"
fi
