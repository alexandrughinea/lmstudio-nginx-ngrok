#!/bin/bash
set -e

echo "==> Generating nginx .htpasswd..."
: "${NGINX_BASIC_AUTH_USERNAME:=admin}"
: "${NGINX_BASIC_AUTH_PASSWORD:=$(openssl rand -base64 24)}"
htpasswd -bc /etc/nginx/.htpasswd "$NGINX_BASIC_AUTH_USERNAME" "$NGINX_BASIC_AUTH_PASSWORD"
echo "    user: $NGINX_BASIC_AUTH_USERNAME"

echo "==> Generating missing secrets..."
: "${VLLM_SQLITE_ENCRYPTION_KEY:=$(openssl rand -base64 32)}"
: "${VLLM_PROXY_RESPONSE_SIGNING_SECRET:=$(openssl rand -base64 32)}"
: "${VLLM_PROXY_REQUEST_SIGNING_SECRET:=}"

echo "==> Ensuring data directory exists..."
SQLITE_DIR="${VLLM_PROXY_SQLITE_PATH:-/workspace/data/vllm-proxy.db}"
mkdir -p "$(dirname "$SQLITE_DIR")"

# ── Write all VLLM_ / PROXY_ env vars to a file so start-fastify.sh can
# source them cleanly, avoiding supervisord quoting issues with special chars.
echo "==> Writing env snapshot for fastify..."
printenv | grep -E '^(VLLM_|PROXY_PORT)' > /tmp/app.env || true

echo "==> Starting services via supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/app.conf
