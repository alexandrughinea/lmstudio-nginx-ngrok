#!/bin/bash
# Sources the env snapshot written by start.sh (avoids supervisord quoting issues)
# then hands off to the Node.js proxy.
set -a
source /tmp/app.env
set +a

# Hardwire the intra-pod addresses — vLLM always runs on localhost:8000
export VLLM_HOST=localhost
export VLLM_PORT=8000
export PROXY_PORT=3000
export VLLM_PROXY_SQLITE_PATH="${VLLM_PROXY_SQLITE_PATH:-/workspace/data/vllm-proxy.db}"

exec node /app/src/server.js
