#!/bin/bash

set -e

echo "Setting up Nginx, Fastify proxy..."

if [ -f .env ]; then
    source .env
else
    echo ".env file not found. Please create it first."
    exit 1
fi

echo "Creating directories..."
mkdir -p nginx/conf.d logs certs

# Generate strong secrets if not provided
SECRETS_GENERATED=false

if [ -z "$NGINX_BASIC_AUTH_PASSWORD" ] || [ "$NGINX_BASIC_AUTH_PASSWORD" = "secure_password_123" ]; then
    echo "No NGINX_BASIC_AUTH_PASSWORD set or using default. Generating password..."
    NGINX_BASIC_AUTH_PASSWORD=$(openssl rand -base64 32)

    if grep -q "^NGINX_BASIC_AUTH_PASSWORD=" .env; then
        sed -i.bak "s|^NGINX_BASIC_AUTH_PASSWORD=.*|NGINX_BASIC_AUTH_PASSWORD=${NGINX_BASIC_AUTH_PASSWORD}|" .env
    else
        echo "NGINX_BASIC_AUTH_PASSWORD=${NGINX_BASIC_AUTH_PASSWORD}" >> .env
    fi

    echo "Generated NGINX_BASIC_AUTH_PASSWORD"
    SECRETS_GENERATED=true
fi

if [ -z "$VLLM_SQLITE_ENCRYPTION_KEY" ]; then
    echo "No \`VLLM_SQLITE_ENCRYPTION_KEY\` set. Generating encryption key..."
    VLLM_SQLITE_ENCRYPTION_KEY=$(openssl rand -base64 32)
    
    if grep -q "^VLLM_SQLITE_ENCRYPTION_KEY=" .env; then
        sed -i.bak "s|^VLLM_SQLITE_ENCRYPTION_KEY=.*|VLLM_SQLITE_ENCRYPTION_KEY=${VLLM_SQLITE_ENCRYPTION_KEY}|" .env
    else
        echo "VLLM_SQLITE_ENCRYPTION_KEY=${VLLM_SQLITE_ENCRYPTION_KEY}" >> .env
    fi
    
    echo "Generated \`VLLM_SQLITE_ENCRYPTION_KEY\`"
    SECRETS_GENERATED=true
fi

if [ -z "$VLLM_PROXY_RESPONSE_SIGNING_SECRET" ]; then
    echo "No \`VLLM_PROXY_RESPONSE_SIGNING_SECRET\` set. Generating signing secret..."
    VLLM_PROXY_RESPONSE_SIGNING_SECRET=$(openssl rand -base64 32)

    if grep -q "^VLLM_PROXY_RESPONSE_SIGNING_SECRET=" .env; then
        sed -i.bak "s|^VLLM_PROXY_RESPONSE_SIGNING_SECRET=.*|VLLM_PROXY_RESPONSE_SIGNING_SECRET=${VLLM_PROXY_RESPONSE_SIGNING_SECRET}|" .env
    else
        echo "VLLM_PROXY_RESPONSE_SIGNING_SECRET=${VLLM_PROXY_RESPONSE_SIGNING_SECRET}" >> .env
    fi

    echo "Generated \`VLLM_PROXY_RESPONSE_SIGNING_SECRET\`"
    SECRETS_GENERATED=true
fi

if [ -z "$VLLM_PROXY_REQUEST_SIGNING_SECRET" ]; then
    echo "No \`VLLM_PROXY_REQUEST_SIGNING_SECRET\` set. Generating request signing secret..."
    VLLM_PROXY_REQUEST_SIGNING_SECRET=$(openssl rand -base64 32)

    if grep -q "^VLLM_PROXY_REQUEST_SIGNING_SECRET=" .env; then
        sed -i.bak "s|^VLLM_PROXY_REQUEST_SIGNING_SECRET=.*|VLLM_PROXY_REQUEST_SIGNING_SECRET=${VLLM_PROXY_REQUEST_SIGNING_SECRET}|" .env
    else
        echo "VLLM_PROXY_REQUEST_SIGNING_SECRET=${VLLM_PROXY_REQUEST_SIGNING_SECRET}" >> .env
    fi

    echo "Generated \`VLLM_PROXY_REQUEST_SIGNING_SECRET\`"
    SECRETS_GENERATED=true
fi

# Clean up backup files
rm -f .env.bak

if [ "$SECRETS_GENERATED" = true ]; then
    echo " Secrets saved to .env)"
fi

echo "Generating nginx configuration from environment..."
if [ -x scripts/nginx/setup.sh ]; then
    scripts/nginx/setup.sh
else
    echo "scripts/nginx/setup.sh not executable, setting +x and retrying..."
    chmod +x scripts/nginx/setup.sh
    scripts/nginx/setup.sh
fi

if [ "$SSL_ENABLED" = "true" ]; then
    echo "Generating SSL certificates..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout certs/server.key \
        -out certs/server.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
    echo "SSL certificates generated"
fi

echo "Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker not found. Please install Docker first."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running. Please start Docker."
    exit 1
fi

if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose not found. Please install Docker Compose."
    exit 1
fi

echo "Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Build containers: make build"
echo "2. Start all services: make start"
echo ""
echo "Configuration:"
echo "- vLLM model: $VLLM_MODEL"
echo "- vLLM backend: ${VLLM_HOST}:${VLLM_PORT}"
echo "- Fastify proxy: port ${PROXY_PORT}"
echo "- Fastify timeout: ${VLLM_PROXY_REQUEST_TIMEOUT}ms ($(( ${VLLM_PROXY_REQUEST_TIMEOUT:-900000} / 1000 ))s)"
echo "- Fastify cache: ${VLLM_PROXY_SQLITE_CACHE:-true}"
echo "- Nginx port: $NGINX_PORT"
echo "- Nginx timeouts: connect=${NGINX_PROXY_CONNECT_TIMEOUT}s, send/read=${NGINX_PROXY_SEND_TIMEOUT}s"
echo "- Auth username: ${NGINX_BASIC_AUTH_USERNAME}"
echo "- Auth password: ${NGINX_BASIC_AUTH_PASSWORD}"
echo "- SSL enabled: $SSL_ENABLED"
