#!/bin/bash
# Sources the env snapshot written by start.sh (avoids supervisord quoting issues)
# then waits for vLLM to be ready before handing off to the Node.js proxy.
set -a
source /tmp/app.env
set +a

# Hardwire the intra-pod addresses — vLLM always runs on localhost:8000
export VLLM_HOST=localhost
export VLLM_PORT=8000
export PROXY_PORT=3000
export VLLM_PROXY_SQLITE_PATH="${VLLM_PROXY_SQLITE_PATH:-/workspace/data/vllm-proxy.db}"

echo "[start-fastify] Waiting for vLLM on localhost:8000..."
until curl -sf http://localhost:8000/v1/models > /dev/null 2>&1; do
  sleep 5
done
echo "[start-fastify] vLLM is ready."

exec node /app/src/server.js
