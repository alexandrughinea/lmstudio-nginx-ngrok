#!/bin/bash

set +e

if [ -f .env ]; then
    source .env
else
    echo ".env file not found."
    exit 1
fi

BASE_URL="https://localhost:${NGINX_SSL_PORT:-8443}"
CURL_OPTS="-k"

AUTH="$NGINX_BASIC_AUTH_USERNAME:$NGINX_BASIC_AUTH_PASSWORD"

echo "Testing LM Studio API through nginx proxy..."
echo ""

echo "1. Testing health endpoint..."
curl -s $CURL_OPTS "$BASE_URL/health" | jq . || echo "Health check response received"
echo ""

echo "2. Testing authentication and listing available models..."
MODELS_BODY='{}'
MODELS_SIGNATURE=""

if [ -n "$LMSTUDIO_PROXY_REQUEST_SIGNING_SECRET" ]; then
    echo "  Signature validation is enabled"
    if command -v node &> /dev/null; then
        echo "  Generating signature..."
        MODELS_SIGNATURE=$(node scripts/test/sign-request.js "$LMSTUDIO_PROXY_REQUEST_SIGNING_SECRET" "$MODELS_BODY" 2>&1)
        if [ $? -eq 0 ] && [ -n "$MODELS_SIGNATURE" ]; then
            echo "  ✓ Signature generated: ${MODELS_SIGNATURE:0:20}..."
        else
            echo "  ✗ Signature generation failed: $MODELS_SIGNATURE"
            echo "  Request will likely fail with 401"
            MODELS_SIGNATURE=""
        fi
    else
        echo "  ✗ Node.js not found - cannot generate signature"
        echo "  Request will likely fail with 401"
    fi
else
    echo "  Signature validation is disabled"
fi

echo "  Making request to $BASE_URL/v1/models..."

if [ -n "$MODELS_SIGNATURE" ]; then
    MODELS_RESPONSE=$(curl -s $CURL_OPTS -w "\nHTTP_STATUS:%{http_code}\nCURL_ERROR:%{errormsg}" -u "$AUTH" \
        -H "x-request-signature: $MODELS_SIGNATURE" \
        "$BASE_URL/v1/models" 2>&1)
else
    MODELS_RESPONSE=$(curl -s $CURL_OPTS -w "\nHTTP_STATUS:%{http_code}\nCURL_ERROR:%{errormsg}" -u "$AUTH" \
        "$BASE_URL/v1/models" 2>&1)
fi

HTTP_STATUS=$(echo "$MODELS_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
CURL_ERROR=$(echo "$MODELS_RESPONSE" | grep "CURL_ERROR:" | cut -d: -f2-)
MODELS_BODY_RESPONSE=$(echo "$MODELS_RESPONSE" | sed '/HTTP_STATUS:/d' | sed '/CURL_ERROR:/d')

echo "  HTTP Status: ${HTTP_STATUS:-unknown}"
if [ -n "$CURL_ERROR" ] && [ "$CURL_ERROR" != "none" ]; then
    echo "  Curl Error: $CURL_ERROR"
fi

if [ "$HTTP_STATUS" = "401" ]; then
    echo "  ✗ Authentication failed (401 Unauthorized)"
    echo "  Response body: $MODELS_BODY_RESPONSE"
    if [ -n "$LMSTUDIO_PROXY_REQUEST_SIGNING_SECRET" ] && [ -z "$MODELS_SIGNATURE" ]; then
        echo ""
        echo "  Issue: Signature validation is enabled but signature generation failed."
        echo "  Solution: Install Node.js or check LMSTUDIO_PROXY_REQUEST_SIGNING_SECRET"
    elif [ -n "$LMSTUDIO_PROXY_REQUEST_SIGNING_SECRET" ]; then
        echo ""
        echo "  Issue: Signature validation failed."
        echo "  Check: LMSTUDIO_PROXY_REQUEST_SIGNING_SECRET matches between backend and proxy"
    fi
    exit 1
elif [ "$HTTP_STATUS" = "200" ]; then
    echo "  ✓ Authentication successful"
    if echo "$MODELS_BODY_RESPONSE" | jq -e '.data' >/dev/null 2>&1; then
        echo "  Available models:"
        echo "$MODELS_BODY_RESPONSE" | jq -r '.data[]?.id // .data[].id' | head -5
        MODEL_COUNT=$(echo "$MODELS_BODY_RESPONSE" | jq '.data | length' 2>/dev/null || echo "unknown")
        echo "  Total models: $MODEL_COUNT"
    else
        echo "  ⚠ Unexpected response format:"
        echo "$MODELS_BODY_RESPONSE" | jq . 2>/dev/null || echo "$MODELS_BODY_RESPONSE"
    fi
else
    echo "  ✗ Request failed with status: ${HTTP_STATUS:-unknown}"
    echo "  Response: $MODELS_BODY_RESPONSE"
    exit 1
fi
echo ""

if [ -z "$LMSTUDIO_MODEL" ]; then
    echo "⚠ LMSTUDIO_MODEL not set, skipping chat completion test"
    echo ""
    echo "✓ API tests completed!"
    exit 0
fi

echo "3. Testing chat completion with model: $LMSTUDIO_MODEL"
if command -v jq &> /dev/null; then
    CHAT_BODY=$(jq -c -n \
      --arg model "$LMSTUDIO_MODEL" \
      '{
        model: $model,
        messages: [{role: "user", content: "Say '\''Hello, this is a test!'\'' and nothing else."}],
        max_tokens: 50,
        temperature: 0.7
      }')
else
    CHAT_BODY="{\"model\":\"$LMSTUDIO_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say 'Hello, this is a test!' and nothing else.\"}],\"max_tokens\":50,\"temperature\":0.7}"
fi

CHAT_SIGNATURE=""
if [ -n "$LMSTUDIO_PROXY_REQUEST_SIGNING_SECRET" ]; then
    echo "  Generating signature..."
    if command -v node &> /dev/null; then
        CHAT_SIGNATURE=$(node scripts/test/sign-request.js "$LMSTUDIO_PROXY_REQUEST_SIGNING_SECRET" "$CHAT_BODY" 2>&1)
        if [ $? -eq 0 ] && [ -n "$CHAT_SIGNATURE" ]; then
            echo "  ✓ Signature generated: ${CHAT_SIGNATURE:0:20}..."
        else
            echo "  ✗ Signature generation failed: $CHAT_SIGNATURE"
            CHAT_SIGNATURE=""
        fi
    else
        echo "  ✗ Node.js not found - cannot generate signature"
    fi
fi

echo "  Sending chat completion request..."
if [ -n "$CHAT_SIGNATURE" ]; then
    CHAT_RESPONSE=$(curl -s $CURL_OPTS -w "\nHTTP_STATUS:%{http_code}" -u "$AUTH" \
        -H "Content-Type: application/json" \
        -H "x-request-signature: $CHAT_SIGNATURE" \
        --data-raw "$CHAT_BODY" \
        "$BASE_URL/v1/chat/completions" 2>&1)
else
    CHAT_RESPONSE=$(curl -s $CURL_OPTS -w "\nHTTP_STATUS:%{http_code}" -u "$AUTH" \
        -H "Content-Type: application/json" \
        --data-raw "$CHAT_BODY" \
        "$BASE_URL/v1/chat/completions" 2>&1)
fi

HTTP_STATUS=$(echo "$CHAT_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
CHAT_BODY_RESPONSE=$(echo "$CHAT_RESPONSE" | sed '/HTTP_STATUS:/d')

echo "  HTTP Status: ${HTTP_STATUS:-unknown}"

if [ "$HTTP_STATUS" = "401" ]; then
    echo "  ✗ Authentication failed (401 Unauthorized)"
    echo "  Response: $CHAT_BODY_RESPONSE"
    exit 1
elif [ "$HTTP_STATUS" = "200" ]; then
    echo "  ✓ Chat completion successful"
    if echo "$CHAT_BODY_RESPONSE" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
        CONTENT=$(echo "$CHAT_BODY_RESPONSE" | jq -r '.choices[0].message.content')
        echo "  Response: $CONTENT"
    else
        echo "  ⚠ Unexpected response format:"
        echo "$CHAT_BODY_RESPONSE" | jq . 2>/dev/null || echo "$CHAT_BODY_RESPONSE"
    fi
else
    echo "  ✗ Request failed with status: ${HTTP_STATUS:-unknown}"
    echo "  Response: $CHAT_BODY_RESPONSE"
    exit 1
fi
echo ""

echo "API tests completed!"
echo ""
echo "Get your public ngrok URL:"
echo "   curl -s http://localhost:4040/api/tunnels | jq '.tunnels[0].public_url'"
