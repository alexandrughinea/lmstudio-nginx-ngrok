#!/bin/bash

set -e

if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

echo "⦿ Stopping LM Studio, Nginx, Ngrok services..."

if command -v lms >/dev/null 2>&1; then
    echo "⦿ Unloading models in LM Studio..."
    LOADED_MODELS=$(lms ps 2>/dev/null | grep -v "No models" || echo "")
    if [ ! -z "$LOADED_MODELS" ]; then
        echo "   Unloading loaded models..."
        lms unload --all 2>/dev/null || echo "   Could not unload models automatically"
    else
        echo "   No models currently loaded"
    fi
else
    echo "LM Studio CLI not available - skipping model unload"
fi

echo "⦿ Stopping Docker services..."
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose down
else
    docker compose down
fi

# Optionally stop LM Studio server
# echo "⦿ Stopping LM Studio server..."
# if command -v lms >/dev/null 2>&1; then
#     lms server stop 2>/dev/null || echo "   Server was not running or could not be stopped"
# fi

echo "Services stopped successfully!"
echo ""
echo "Note: LM Studio server is still running locally."
echo "   To stop it manually: lms server stop"
echo "   Or kill the process: pkill -f 'LM Studio'"
