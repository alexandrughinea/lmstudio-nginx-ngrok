#!/bin/bash

set -e

if [ -f .env ]; then
    source .env
fi

echo "⦿ Service Status:"
docker-compose ps
echo ""

echo "⦿ LM Studio Status:"
if command -v lms >/dev/null 2>&1; then
    LMS_STATUS=$(lms server status 2>&1)
    if [ $? -eq 0 ] && [ -n "$LMS_STATUS" ]; then
        echo "$LMS_STATUS"
        MODEL_COUNT=$(curl -s http://localhost:${LMSTUDIO_PORT:-1234}/v1/models 2>/dev/null | jq -r '.data | length' 2>/dev/null || echo "")
        if [ -n "$MODEL_COUNT" ] && [ "$MODEL_COUNT" -gt 0 ]; then
            echo "Models loaded: $MODEL_COUNT"
        fi
    else
        echo "LM Studio CLI available but server not running"
    fi
else
    if curl -s http://localhost:${LMSTUDIO_PORT:-1234}/v1/models >/dev/null 2>&1; then
        echo "LM Studio server running on port ${LMSTUDIO_PORT:-1234}"
        MODEL_COUNT=$(curl -s http://localhost:${LMSTUDIO_PORT:-1234}/v1/models 2>/dev/null | jq -r '.data | length' 2>/dev/null || echo "")
        if [ -n "$MODEL_COUNT" ] && [ "$MODEL_COUNT" -gt 0 ]; then
            echo "Models loaded: $MODEL_COUNT"
        fi
    else
        echo "LM Studio server not accessible on port ${LMSTUDIO_PORT:-1234}"
    fi
fi
echo ""

echo "⦿ Ngrok Status:"
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | jq -r '.tunnels[0].public_url // "Not available"' 2>/dev/null)
if [ "$NGROK_URL" != "Not available" ] && [ -n "$NGROK_URL" ]; then
    echo "$NGROK_URL"
else
    echo "Ngrok not running or no tunnels available"
fi
echo ""

echo "⦿ Health Check:"
if [ -n "${NGINX_PORT}" ]; then
    if curl -s http://localhost:${NGINX_PORT}/health >/dev/null 2>&1; then
        echo "Nginx proxy health check: OK"
    else
        echo "Nginx proxy health check: FAILED"
    fi
else
    echo "NGINX_PORT not configured"
fi
