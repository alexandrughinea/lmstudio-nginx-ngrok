#!/bin/bash

set -e

if [ -f .env ]; then
    source .env
fi

echo "⦿ Service Status:"
docker-compose ps
echo ""

echo "⦿ vLLM Backend Status:"
if command -v lms >/dev/null 2>&1; then
    LMS_STATUS=$(lms server status 2>&1)
    if [ $? -eq 0 ] && [ -n "$LMS_STATUS" ]; then
        echo "$LMS_STATUS"
        MODEL_COUNT=$(curl -s http://localhost:${VLLM_PORT:-8000}/v1/models 2>/dev/null | jq -r '.data | length' 2>/dev/null || echo "")
        if [ -n "$MODEL_COUNT" ] && [ "$MODEL_COUNT" -gt 0 ]; then
            echo "Available models: $MODEL_COUNT"
        fi
    else
        echo "LMS CLI available but server not running"
    fi
else
    if curl -s http://localhost:${VLLM_PORT:-8000}/v1/models >/dev/null 2>&1; then
        echo "vLLM server running on port ${VLLM_PORT:-8000}"
        MODEL_COUNT=$(curl -s http://localhost:${VLLM_PORT:-8000}/v1/models 2>/dev/null | jq -r '.data | length' 2>/dev/null || echo "")
        if [ -n "$MODEL_COUNT" ] && [ "$MODEL_COUNT" -gt 0 ]; then
            echo "Available models: $MODEL_COUNT"
        fi
    else
        echo "vLLM server not accessible on port ${VLLM_PORT:-8000}"
    fi
fi
echo ""

echo "⦿ Health Check:"
if [ -n "${NGINX_SSL_PORT}" ]; then
    if curl -sk https://localhost:${NGINX_SSL_PORT}/health >/dev/null 2>&1; then
        echo "Nginx proxy health check: OK"
    else
        echo "Nginx proxy health check: FAILED"
    fi
else
    echo "NGINX_SSL_PORT not configured"
fi

echo ""
echo "⦿ Fastify Proxy Status:"
if docker ps --format '{{.Names}}' | grep -q '^vllm-fastify-proxy$'; then
    if docker exec vllm-fastify-proxy curl -s http://localhost:3000/health >/dev/null 2>&1; then
        echo "Fastify proxy health check: OK"
    else
        echo "Fastify proxy health check: FAILED"
    fi
else
    echo "Fastify proxy container not running"
fi
