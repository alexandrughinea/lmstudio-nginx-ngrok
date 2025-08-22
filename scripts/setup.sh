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

echo "Setting up authentication..."
if command -v htpasswd >/dev/null 2>&1; then
    htpasswd -bc nginx/.htpasswd "$AUTH_USERNAME" "$AUTH_PASSWORD"
    echo "Authentication file created with username: $AUTH_USERNAME"
else
    echo "htpasswd not found. Installing apache2-utils..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew >/dev/null 2>&1; then
            brew install httpd
        else
            echo "Please install Homebrew first: https://brew.sh/"
            exit 1
        fi
    else
        sudo apt-get update && sudo apt-get install -y apache2-utils
    fi
    htpasswd -bc nginx/.htpasswd "$AUTH_USERNAME" "$AUTH_PASSWORD"
    echo "Authentication file created with username: $AUTH_USERNAME"
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
echo "   - Nginx port: $NGINX_PORT"
echo "   - VLLM Bridge: $VLLM_BRIDGE_ENABLED (port: $VLLM_BRIDGE_PORT)"
echo "   - Auth username: $AUTH_USERNAME"
echo "   - SSL enabled: $SSL_ENABLED"
