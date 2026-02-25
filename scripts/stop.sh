#!/bin/bash

set -e

if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

echo "⦿ Stopping Fastify proxy, Nginx services..."

echo "⦿ Stopping Docker services..."
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose down
else
    docker compose down
fi

echo "Services stopped successfully!"
