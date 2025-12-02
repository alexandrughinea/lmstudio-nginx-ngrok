#!/bin/bash

set -e

if [ -f .env ]; then
    source .env
else
    echo ".env file not found."
    exit 1
fi

BASE_URL="http://localhost:$NGINX_PORT"
AUTH="$NGINX_BASIC_AUTH_USERNAME:$NGINX_BASIC_AUTH_PASSWORD"

echo "Testing LM Studio API through nginx proxy..."
echo ""

echo "1. Testing health endpoint..."
curl -s "$BASE_URL/health" | jq . || echo "Health check response received"
echo ""

echo "2. Testing authentication..."
if curl -s -u "$AUTH" "$BASE_URL/api/tags" >/dev/null; then
    echo "Authentication successful"
else
    echo "Authentication failed"
    exit 1
fi
echo ""

echo "3. Listing available models..."
MODELS_RESPONSE=$(curl -s -u "$AUTH" "$BASE_URL/v1/models")
if echo "$MODELS_RESPONSE" | jq -e '.data' >/dev/null 2>&1; then
    echo "$MODELS_RESPONSE" | jq -r '.data[].id'
else
    echo "No models available or unexpected response format"
fi
echo ""

echo "4. Testing chat completion with model: $LMSTUDIO_MODEL"
CHAT_RESPONSE=$(curl -s -u "$AUTH" "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$LMSTUDIO_MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Hello, how are you?\"}],
    \"max_tokens\": 50
  }")
if echo "$CHAT_RESPONSE" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
    echo "$CHAT_RESPONSE" | jq -r '.choices[0].message.content'
else
    echo "Chat completion failed or no response"
fi
echo ""

echo "API tests completed!"
echo ""
echo "Get your public ngrok URL:"
echo "   curl -s http://localhost:4040/api/tunnels | jq '.tunnels[0].public_url'"
