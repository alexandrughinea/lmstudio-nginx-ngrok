#!/bin/bash

set -e

echo "Setting up LM Studio, Nginx, Ngrok proxy..."

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

if [ -z "$LMSTUDIO_SQLITE_ENCRYPTION_KEY" ]; then
    echo "No `LMSTUDIO_SQLITE_ENCRYPTION_KEY` set. Generating encryption key..."
    LMSTUDIO_SQLITE_ENCRYPTION_KEY=$(openssl rand -base64 32)
    
    if grep -q "^LMSTUDIO_SQLITE_ENCRYPTION_KEY=" .env; then
        sed -i.bak "s|^LMSTUDIO_SQLITE_ENCRYPTION_KEY=.*|LMSTUDIO_SQLITE_ENCRYPTION_KEY=${LMSTUDIO_SQLITE_ENCRYPTION_KEY}|" .env
    else
        echo "LMSTUDIO_SQLITE_ENCRYPTION_KEY=${LMSTUDIO_SQLITE_ENCRYPTION_KEY}" >> .env
    fi
    
    echo "Generated `LMSTUDIO_SQLITE_ENCRYPTION_KEY`"
    SECRETS_GENERATED=true
fi

if [ -z "$LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET" ]; then
    echo "No `LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET` set. Generating signing secret..."
    LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET=$(openssl rand -base64 32)
    
    if grep -q "^LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET=" .env; then
        sed -i.bak "s|^LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET=.*|LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET=${LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET}|" .env
    else
        echo "LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET=${LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET}" >> .env
    fi
    
    echo "Generated `LMSTUDIO_PROXY_RESPONSE_SIGNING_SECRET`"
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

echo "Checking LM Studio CLI..."
if ! command -v lms >/dev/null 2>&1; then
    echo "LM Studio CLI (lms) not found"
    echo "   Please install LM Studio from: https://lmstudio.ai/"
    echo "   The CLI should be available after installation"
    exit 1
fi

echo "Checking LM Studio status..."
LMS_STATUS=$(lms status 2>/dev/null || echo "error")
if [[ "$LMS_STATUS" == *"error"* ]]; then
    echo "Could not get LM Studio status"
    echo "   Please ensure LM Studio is properly installed and accessible"
else
    echo "LM Studio CLI is working"
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
echo "1. Update your .env file with your ngrok auth token"
echo "2. Configure VLLM bridge: Set VLLM_BRIDGE_ENABLED=true/false in .env"
echo "3. Run './start.sh' to start all services"
echo "4. Access the ngrok web interface at http://localhost:4040"
echo ""
echo "- Configuration:"
echo "   - LM Studio model: $LMSTUDIO_MODEL"
echo "   - LM Studio: ${LMSTUDIO_HOST}:${LMSTUDIO_PORT}"
echo "   - Fastify proxy: port ${PROXY_PORT:-3000}"
echo "   - Fastify timeout: ${LMSTUDIO_PROXY_REQUEST_TIMEOUT:-900000}ms ($(( ${LMSTUDIO_PROXY_REQUEST_TIMEOUT:-900000} / 1000 ))s)"
echo "   - Fastify cache: ${LMSTUDIO_PROXY_SQLITE_CACHE:-true}"
echo "   - Nginx port: $NGINX_PORT"
echo "   - Nginx timeouts: connect=${NGINX_PROXY_CONNECT_TIMEOUT:-120}s, send/read=${NGINX_PROXY_SEND_TIMEOUT:-900}s"
echo "   - VLLM Bridge: $VLLM_BRIDGE_ENABLED (port: $VLLM_BRIDGE_PORT)"
echo "   - Auth username: ${NGINX_BASIC_AUTH_USERNAME:-admin}"
echo "   - SSL enabled: $SSL_ENABLED"
