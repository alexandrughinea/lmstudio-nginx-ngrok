#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE" >&2
    exit 1
fi

source "$ENV_FILE"

if [ -z "$NGINX_BASIC_AUTH_USERNAME" ] || [ -z "$NGINX_BASIC_AUTH_PASSWORD" ]; then
    echo "Error: NGINX_BASIC_AUTH_USERNAME or NGINX_BASIC_AUTH_PASSWORD is not set in .env" >&2
    exit 1
fi

ENCODED=$(echo -n "$NGINX_BASIC_AUTH_USERNAME:$NGINX_BASIC_AUTH_PASSWORD" | base64)

echo "Authorization: Basic $ENCODED"
