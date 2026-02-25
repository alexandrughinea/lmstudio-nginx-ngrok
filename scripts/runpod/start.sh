#!/bin/bash
set -e

echo "==> Generating nginx .htpasswd..."
: "${NGINX_BASIC_AUTH_USERNAME:=admin}"
: "${NGINX_BASIC_AUTH_PASSWORD:=$(openssl rand -base64 24)}"
# Use bcrypt (-B) and read password from stdin (-i) to avoid exposing it in ps aux
printf '%s' "$NGINX_BASIC_AUTH_PASSWORD" | htpasswd -B -c -i /etc/nginx/.htpasswd "$NGINX_BASIC_AUTH_USERNAME"
echo "    user: $NGINX_BASIC_AUTH_USERNAME"

echo "==> Generating missing secrets..."
: "${VLLM_SQLITE_ENCRYPTION_KEY:=$(openssl rand -base64 32)}"
: "${VLLM_PROXY_RESPONSE_SIGNING_SECRET:=$(openssl rand -base64 32)}"
: "${VLLM_PROXY_REQUEST_SIGNING_SECRET:=}"

# Defaults for vLLM flags used in supervisord %(ENV_*)s substitutions.
# If not set by the RunPod template, these values are used.
: "${VLLM_MODEL:=facebook/opt-125m}"
: "${VLLM_DTYPE:=auto}"
: "${VLLM_MAX_MODEL_LEN:=4096}"

export VLLM_MODEL VLLM_DTYPE VLLM_MAX_MODEL_LEN

echo "==> Ensuring data directory exists..."
SQLITE_DIR="${VLLM_PROXY_SQLITE_PATH:-/workspace/data/vllm-proxy.db}"
mkdir -p "$(dirname "$SQLITE_DIR")"

# ── Write all VLLM_ / PROXY_ env vars to a file so start-fastify.sh can
# source them cleanly, avoiding supervisord quoting issues with special chars.
echo "==> Writing env snapshot for fastify..."
printenv | grep -E '^(VLLM_|PROXY_PORT)' | while IFS= read -r line; do
  key="${line%%=*}"
  val="${line#*=}"
  printf '%s=%q\n' "$key" "$val"
done > /tmp/app.env || true

echo "==> Starting services via supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/app.conf
