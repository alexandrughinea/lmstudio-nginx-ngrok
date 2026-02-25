#!/bin/bash
# E2E test suite for the local / RunPod stack (HTTP, port 8080).
# Run after: docker compose -f docker-compose.yml -f docker-compose.local.yml up --build
#
# Usage:
#   ./scripts/test/test-local.sh
#   BASE_URL=http://localhost:8080 ./scripts/test/test-local.sh

set +e

# ── Config ────────────────────────────────────────────────────────────────────
if [ -f .env ]; then source .env; fi

BASE_URL="${BASE_URL:-http://localhost:8080}"
AUTH="${NGINX_BASIC_AUTH_USERNAME:-admin}:${NGINX_BASIC_AUTH_PASSWORD}"
SIGN_SECRET="${VLLM_PROXY_REQUEST_SIGNING_SECRET:-}"
MODEL="${VLLM_MODEL:-}"
SQLITE_PATH="${VLLM_PROXY_SQLITE_HOST_DIR:-./fastify-proxy/data}/vllm-proxy.db"

PASS=0; FAIL=0

# ── Helpers ───────────────────────────────────────────────────────────────────
green()  { printf "\033[32m✓\033[0m %s\n" "$*"; }
red()    { printf "\033[31m✗\033[0m %s\n" "$*"; }
yellow() { printf "\033[33m⚠\033[0m %s\n" "$*"; }
header() { echo; printf "\033[1m%s\033[0m\n" "$*"; }

pass() { green "$1"; (( PASS++ )); }
fail() { red   "$1"; (( FAIL++ )); }

sign() {
  local secret="$1" body="$2"
  [ -z "$secret" ] && echo "" && return
  node scripts/test/sign-request.js "$secret" "$body" 2>/dev/null
}

status_of() {
  # Returns just the HTTP status code for a curl response string
  echo "$1" | grep "^HTTP_STATUS:" | cut -d: -f2 | tr -d '[:space:]'
}

body_of() {
  echo "$1" | grep -v "^HTTP_STATUS:"
}

curl_get() {
  local url="$1"; shift
  curl -s -w "\nHTTP_STATUS:%{http_code}" "$@" "$url" 2>/dev/null
}

curl_post() {
  local url="$1" body="$2"; shift 2
  curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -H "Content-Type: application/json" \
    --data-raw "$body" "$@" "$url" 2>/dev/null
}

# ── 1. Stack reachability ─────────────────────────────────────────────────────
header "1. Stack reachability"

r=$(curl_get "$BASE_URL/health")
s=$(status_of "$r")
if [ "$s" = "200" ]; then
  pass "GET /health → 200"
  STATUS_BODY=$(body_of "$r")
  echo "   $(echo "$STATUS_BODY" | jq -c '{status:.status}' 2>/dev/null || echo "$STATUS_BODY")"
else
  fail "GET /health → expected 200, got ${s:-no response} (is the stack running?)"
fi

# ── 2. Authentication ─────────────────────────────────────────────────────────
header "2. Authentication"

r=$(curl_get "$BASE_URL/v1/models")
s=$(status_of "$r")
[ "$s" = "401" ] && pass "No credentials → 401" || fail "No credentials → expected 401, got $s"

r=$(curl_get "$BASE_URL/v1/models" -u "admin:wrongpassword")
s=$(status_of "$r")
[ "$s" = "401" ] && pass "Wrong password → 401" || fail "Wrong password → expected 401, got $s"

# When signing is enforced, include the signature so this tests auth only
MODELS_SIG_FOR_AUTH=$(sign "$SIGN_SECRET" '{}')
AUTH_EXTRA=()
[ -n "$MODELS_SIG_FOR_AUTH" ] && AUTH_EXTRA+=(-H "x-request-signature: $MODELS_SIG_FOR_AUTH")

r=$(curl_get "$BASE_URL/v1/models" -u "$AUTH" "${AUTH_EXTRA[@]}")
s=$(status_of "$r")
if [ "$s" = "200" ]; then
  pass "Correct credentials → 200"
  MODEL_COUNT=$(body_of "$r" | jq '.data | length' 2>/dev/null || echo "?")
  echo "   Backend reports $MODEL_COUNT model(s)"
else
  fail "Correct credentials → expected 200, got $s"
  echo "   Response: $(body_of "$r")"
fi

# ── 3. Request signing ────────────────────────────────────────────────────────
header "3. Request signing"

MODELS_BODY='{}'
SIG=$(sign "$SIGN_SECRET" "$MODELS_BODY")

if [ -z "$SIGN_SECRET" ]; then
  yellow "VLLM_PROXY_REQUEST_SIGNING_SECRET not set — signing tests skipped"
else
  r=$(curl_get "$BASE_URL/v1/models" -u "$AUTH")
  s=$(status_of "$r")
  [ "$s" = "401" ] && pass "Missing signature → 401" || fail "Missing signature → expected 401, got $s"

  r=$(curl_get "$BASE_URL/v1/models" -u "$AUTH" -H "x-request-signature: badhash")
  s=$(status_of "$r")
  [ "$s" = "401" ] && pass "Bad signature → 401" || fail "Bad signature → expected 401, got $s"

  if [ -n "$SIG" ]; then
    r=$(curl_get "$BASE_URL/v1/models" -u "$AUTH" -H "x-request-signature: $SIG")
    s=$(status_of "$r")
    [ "$s" = "200" ] && pass "Valid signature → 200" || fail "Valid signature → expected 200, got $s"
  else
    yellow "Could not generate signature (node not found?) — skipping valid-sig test"
  fi
fi

# ── 4. Response signing ───────────────────────────────────────────────────────
header "4. Response signing (x-response-signature header)"

RESP_SECRET="${VLLM_PROXY_RESPONSE_SIGNING_SECRET:-}"
if [ -z "$RESP_SECRET" ]; then
  yellow "VLLM_PROXY_RESPONSE_SIGNING_SECRET not set — response signing tests skipped"
else
  EXTRA_HEADERS=()
  [ -n "$SIG" ] && EXTRA_HEADERS+=(-H "x-request-signature: $SIG")

  r=$(curl -s -D - -o /dev/null -u "$AUTH" "${EXTRA_HEADERS[@]}" "$BASE_URL/v1/models" 2>/dev/null)
  if echo "$r" | grep -qi "x-response-signature:"; then
    pass "x-response-signature header present on /v1/models"
  else
    fail "x-response-signature header missing"
  fi
fi

# ── 5. Models endpoint ────────────────────────────────────────────────────────
header "5. /v1/models"

EXTRA=()
[ -n "$SIG" ] && EXTRA+=(-H "x-request-signature: $SIG")

r=$(curl_get "$BASE_URL/v1/models" -u "$AUTH" "${EXTRA[@]}")
s=$(status_of "$r")
b=$(body_of "$r")
if [ "$s" = "200" ] && echo "$b" | jq -e '.data' >/dev/null 2>&1; then
  pass "/v1/models returns valid OpenAI-format response"
  echo "$b" | jq -r '.data[].id' 2>/dev/null | head -5 | sed 's/^/   - /'
else
  fail "/v1/models unexpected response (status=$s)"
  echo "   $b"
fi

# ── 6. Chat completion ────────────────────────────────────────────────────────
header "6. Chat completion"

if [ -z "$MODEL" ]; then
  yellow "VLLM_MODEL not set — chat completion tests skipped"
else
  CHAT_BODY=$(jq -c -n \
    --arg id  "e2e-test-$(date +%s)" \
    --arg model "$MODEL" \
    '{id: $id, model: $model,
      messages: [{role:"user", content:"Reply with the single word: pong"}],
      max_tokens: 10, temperature: 0}' 2>/dev/null)

  [ -z "$CHAT_BODY" ] && CHAT_BODY="{\"id\":\"e2e-test-$$\",\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word: pong\"}],\"max_tokens\":10,\"temperature\":0}"

  CHAT_SIG=$(sign "$SIGN_SECRET" "$CHAT_BODY")
  CHAT_EXTRA=()
  [ -n "$CHAT_SIG" ] && CHAT_EXTRA+=(-H "x-request-signature: $CHAT_SIG")

  r=$(curl_post "$BASE_URL/v1/chat/completions" "$CHAT_BODY" -u "$AUTH" "${CHAT_EXTRA[@]}")
  s=$(status_of "$r")
  b=$(body_of "$r")

  if [ "$s" = "200" ]; then
    pass "POST /v1/chat/completions → 200"
    CONTENT=$(echo "$b" | jq -r '.choices[0].message.content' 2>/dev/null)
    echo "   Model replied: \"$CONTENT\""
  else
    fail "POST /v1/chat/completions → expected 200, got $s"
    echo "   $b"
  fi

fi

# ── 7. SQLite cache ───────────────────────────────────────────────────────────
header "7. SQLite cache"

if [ "${VLLM_PROXY_SQLITE_CACHE:-true}" = "false" ]; then
  yellow "VLLM_PROXY_SQLITE_CACHE=false — cache tests skipped"
elif [ ! -f "$SQLITE_PATH" ]; then
  yellow "DB file not found at $SQLITE_PATH — run a request first (or check VLLM_PROXY_SQLITE_HOST_DIR)"
else
  DB_SIZE=$(du -h "$SQLITE_PATH" | cut -f1)
  pass "SQLite DB exists ($DB_SIZE) at $SQLITE_PATH"

  if command -v sqlite3 >/dev/null 2>&1; then
    REQ_COUNT=$(sqlite3 "$SQLITE_PATH" "SELECT COUNT(*) FROM requests;" 2>/dev/null || echo "?")
    RES_COUNT=$(sqlite3 "$SQLITE_PATH" "SELECT COUNT(*) FROM responses;" 2>/dev/null || echo "?")
    echo "   requests table: $REQ_COUNT rows"
    echo "   responses table: $RES_COUNT rows"

    if [ "$REQ_COUNT" != "?" ] && [ "$REQ_COUNT" -gt 0 ] 2>/dev/null; then
      pass "Requests are being stored in SQLite"
    else
      yellow "No requests in DB yet (did chat completion run?)"
    fi
  else
    yellow "sqlite3 CLI not installed — skipping row count check"
  fi
fi

# ── 8. Rate limiting ──────────────────────────────────────────────────────────
header "8. Rate limiting"

RATE_HIT=false
for i in {1..30}; do
  r=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health" 2>/dev/null)
  if [ "$r" = "429" ] || [ "$r" = "503" ]; then
    RATE_HIT=true
    echo "   Rate limit triggered on request $i (HTTP $r)"
    break
  fi
done

$RATE_HIT && pass "Rate limiting triggers on burst traffic" \
           || yellow "Rate limit not triggered in 30 rapid requests (limit may be higher than burst)"

# ── 9. Security headers ───────────────────────────────────────────────────────
header "9. Security headers"

HDR=$(curl -s -I "$BASE_URL/health" 2>/dev/null)

for h in "X-Frame-Options" "X-Content-Type-Options" "X-XSS-Protection"; do
  if echo "$HDR" | grep -qi "^$h:"; then
    pass "$h present"
  else
    fail "$h missing"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$(( PASS + FAIL ))
if [ $FAIL -eq 0 ]; then
  printf "\033[32mAll %d tests passed\033[0m\n" "$TOTAL"
else
  printf "\033[32m%d passed\033[0m  \033[31m%d failed\033[0m  (total: %d)\n" "$PASS" "$FAIL" "$TOTAL"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ $FAIL -eq 0 ] && exit 0 || exit 1
