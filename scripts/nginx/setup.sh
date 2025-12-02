#!/usr/bin/env bash
set -euo pipefail

# Determine project root (one level up from this script's directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR%/scripts/nginx}"

cd "$PROJECT_ROOT"

if [[ ! -f .env ]]; then
  echo ".env not found in project root: $PROJECT_ROOT" >&2
  exit 1
fi

# shellcheck disable=SC1091
source .env

# Defaults under NGINX_PROXY_* namespace
NGINX_PROXY_RATE_LIMIT="${NGINX_PROXY_RATE_LIMIT:-10r/s}"
NGINX_PROXY_RATE_BURST="${NGINX_PROXY_RATE_BURST:-20}"

NGINX_PROXY_CONNECT_TIMEOUT="${NGINX_PROXY_CONNECT_TIMEOUT:-90}"
NGINX_PROXY_SEND_TIMEOUT="${NGINX_PROXY_SEND_TIMEOUT:-330}"
NGINX_PROXY_READ_TIMEOUT="${NGINX_PROXY_READ_TIMEOUT:-330}"
NGINX_KEEPALIVE_TIMEOUT="${NGINX_KEEPALIVE_TIMEOUT:-900}"
NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-10M}"
SSL_ENABLED="${SSL_ENABLED:-false}"

# Create directories
mkdir -p nginx/conf.d

# Generate main nginx.conf
NGINX_CONF="nginx/nginx.conf"
cat > "$NGINX_CONF" <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log /var/log/nginx/access.log main;

    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
EOF

echo "    keepalive_timeout ${NGINX_KEEPALIVE_TIMEOUT};" >> "$NGINX_CONF"

cat >> "$NGINX_CONF" <<'EOF'
    types_hash_max_size 2048;
    server_tokens off;

    # Rate limiting zone
EOF

echo "    limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=${NGINX_PROXY_RATE_LIMIT};" >> "$NGINX_CONF"

cat >> "$NGINX_CONF" <<'EOF'

    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Include server configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

# Generate default.conf
OUT_FILE="nginx/conf.d/default.conf"

cat > "$OUT_FILE" <<EOF
server {
    listen 80;
    server_name _;

    # Basic settings
    client_max_body_size ${NGINX_CLIENT_MAX_BODY_SIZE};

    # Global authentication
    auth_basic "LM Studio API Access";
    auth_basic_user_file /etc/nginx/.htpasswd;

    # LM Studio OpenAI-compatible endpoints via Fastify proxy (for caching & webhooks)
    location /v1/ {
        # Rate limiting (zone defined in nginx.conf)
        limit_req zone=api_limit burst=${NGINX_PROXY_RATE_BURST} nodelay;

        proxy_pass http://fastify-proxy:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout ${NGINX_PROXY_CONNECT_TIMEOUT}s;
        proxy_send_timeout ${NGINX_PROXY_SEND_TIMEOUT}s;
        proxy_read_timeout ${NGINX_PROXY_READ_TIMEOUT}s;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    }

    # Health check (no authentication, no rate limiting)
    location /health {
        auth_basic off;
        proxy_pass http://fastify-proxy:3000;
        proxy_set_header Host \$host;
    }

    # All other endpoints go directly to Fastify proxy
    location / {
        # Rate limiting (zone defined in nginx.conf)
        limit_req zone=api_limit burst=${NGINX_PROXY_RATE_BURST} nodelay;

        proxy_pass http://fastify-proxy:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout ${NGINX_PROXY_CONNECT_TIMEOUT}s;
        proxy_send_timeout ${NGINX_PROXY_SEND_TIMEOUT}s;
        proxy_read_timeout ${NGINX_PROXY_READ_TIMEOUT}s;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    }
}
EOF

# Generate SSL server block if enabled
if [ "$SSL_ENABLED" = "true" ]; then
    cat >> "$OUT_FILE" <<'EOF'

server {
    listen 443 ssl http2;
    server_name _;

    # SSL configuration
    ssl_certificate /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Basic settings
EOF
    echo "    client_max_body_size ${NGINX_CLIENT_MAX_BODY_SIZE};" >> "$OUT_FILE"
    cat >> "$OUT_FILE" <<'EOF'

    # Global authentication
    auth_basic "LM Studio API Access";
    auth_basic_user_file /etc/nginx/.htpasswd;

    # LM Studio OpenAI-compatible endpoints via Fastify proxy
    location /v1/ {
EOF
    cat >> "$OUT_FILE" <<EOF
        # Rate limiting
        limit_req zone=api_limit burst=${NGINX_PROXY_RATE_BURST} nodelay;

        proxy_pass http://fastify-proxy:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_connect_timeout ${NGINX_PROXY_CONNECT_TIMEOUT}s;
        proxy_send_timeout ${NGINX_PROXY_SEND_TIMEOUT}s;
        proxy_read_timeout ${NGINX_PROXY_READ_TIMEOUT}s;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    }

    # Health check (no authentication, no rate limiting)
    location /health {
        auth_basic off;
        proxy_pass http://fastify-proxy:3000;
        proxy_set_header Host \$host;
    }

    # All other endpoints
    location / {
        # Rate limiting
        limit_req zone=api_limit burst=${NGINX_PROXY_RATE_BURST} nodelay;

        proxy_pass http://fastify-proxy:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_connect_timeout ${NGINX_PROXY_CONNECT_TIMEOUT}s;
        proxy_send_timeout ${NGINX_PROXY_SEND_TIMEOUT}s;
        proxy_read_timeout ${NGINX_PROXY_READ_TIMEOUT}s;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    }
}
EOF
fi

# Regenerate basic auth file (nginx/.htpasswd)
echo "Setting up nginx basic authentication..."
if command -v htpasswd >/dev/null 2>&1; then
  htpasswd -bc nginx/.htpasswd "${NGINX_BASIC_AUTH_USERNAME:-admin}" "$NGINX_BASIC_AUTH_PASSWORD" >/dev/null 2>&1 || true
  echo "  - nginx/.htpasswd created for user: ${NGINX_BASIC_AUTH_USERNAME:-admin}"
else
  echo "htpasswd not found. Installing apache2-utils for nginx auth..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew install httpd
    else
      echo "Please install Homebrew first: https://brew.sh/" >&2
      exit 1
    fi
  else
    sudo apt-get update && sudo apt-get install -y apache2-utils
  fi
  htpasswd -bc nginx/.htpasswd "${NGINX_BASIC_AUTH_USERNAME:-admin}" "$NGINX_BASIC_AUTH_PASSWORD" >/dev/null 2>&1 || true
  echo "  - nginx/.htpasswd created for user: ${NGINX_BASIC_AUTH_USERNAME:-admin}"
fi

echo "Generated nginx configuration files:"
echo "  - $NGINX_CONF"
echo "  - $OUT_FILE"
echo ""
echo "Using env values:"
echo "  SSL_ENABLED=${SSL_ENABLED}"
echo "  NGINX_CLIENT_MAX_BODY_SIZE=${NGINX_CLIENT_MAX_BODY_SIZE}"
echo "  NGINX_KEEPALIVE_TIMEOUT=${NGINX_KEEPALIVE_TIMEOUT}s"
echo "  NGINX_PROXY_RATE_LIMIT=${NGINX_PROXY_RATE_LIMIT}"
echo "  NGINX_PROXY_RATE_BURST=${NGINX_PROXY_RATE_BURST}"
echo "  NGINX_PROXY_CONNECT_TIMEOUT=${NGINX_PROXY_CONNECT_TIMEOUT}s"
echo "  NGINX_PROXY_SEND_TIMEOUT=${NGINX_PROXY_SEND_TIMEOUT}s"
echo "  NGINX_PROXY_READ_TIMEOUT=${NGINX_PROXY_READ_TIMEOUT}s"
