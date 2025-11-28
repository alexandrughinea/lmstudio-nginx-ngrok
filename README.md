# LM Studio Nginx Ngrok Setup

This project provides a secure tunnel, authenticated proxy setup for LM Studio API access through **nginx**, a **Fastify proxy with SQLite logging**, and **ngrok**.

- **LM Studio Integration** - OpenAI-compatible `/v1/*` API proxied through a Fastify service
- **Request/Response Logging** - All `/v1/*` requests and responses are stored in a local SQLite DB
- **Security** - Basic authentication at nginx, rate limiting, security headers  
- **Public Access** - Ngrok tunnel for external access
- **Monitoring** - Health checks, status script, and access logging
- **Containerized** - nginx, Fastify proxy, and ngrok run in Docker; LM Studio runs locally
- **Easy Setup** - Automated setup and management scripts / Makefile targets

## Quick Start

1. **Clone and setup:**
   ```bash
   cd lmstudio-nginx-ngrok
   chmod +x scripts/*.sh
   ./scripts/setup.sh
   ```

2. **Configure LM Studio model** (optional):
   Edit `.env` file with your settings:
   ```bash
   export LMSTUDIO_MODEL="your-preferred-model"
   NGROK_AUTHTOKEN=your_token   # Get from https://dashboard.ngrok.com
   AUTH_USERNAME=admin          # API username
   AUTH_PASSWORD=secure_pass    # API password
   ```

3. **Start services:**
   ```bash
   # using Makefile
   make start

   # or directly
   ./scripts/start.sh
   ```

4. **Test the OpenAI-compatible API:**
   ```bash
   # List models (proxied through nginx → fastify → LM Studio)
   curl -u admin:secure_pass "http://localhost:8080/v1/models"

   # Simple chat completion
   curl -u admin:secure_pass \
     -H "Content-Type: application/json" \
     -d '{
       "model": "your-model",
       "messages": [{"role": "user", "content": "Hello!"}],
       "stream": false
     }' \
     "http://localhost:8080/v1/chat/completions"
   ```

## LM Studio Configuration

### Environment Variables

| Variable                               | Description                                                                 | Default                 |
|----------------------------------------|-----------------------------------------------------------------------------|-------------------------|
| `LMSTUDIO_MODEL`                       | LM Studio model to use (must be available in LM Studio)                    | `google/gemma-3-12b`   |
| `LMSTUDIO_HOST`                        | LM Studio server host                                                      | `localhost`             |
| `LMSTUDIO_PORT`                        | LM Studio server port                                                      | `1234`                  |
| `LMSTUDIO_SQLITE_HOST_DIR`             | Host directory for Fastify SQLite DB                                       | `./fastify-proxy/data`  |
| `LMSTUDIO_WEBHOOK_ON_CHAT_COMPLETE`    | Optional webhook URL fired after chat completions                          | _empty_                 |
| `LMSTUDIO_WEBHOOK_ON_CHAT_COMPLETE_HEADERS` | Optional JSON headers sent with the webhook request                   | _empty_                 |
| `LMSTUDIO_SQLITE_LOGGING`              | Enable/disable SQLite logging (`"false" to disable)                        | `true`                  |
| `LMSTUDIO_SQLITE_PRIVACY_TRIM`         | When `true`, store only trimmed+hashed request/response bodies in SQLite   | `false`                 |
| `LMSTUDIO_REQUEST_TIMEOUT`             | Timeout for LM Studio requests in milliseconds (for long inference tasks)  | `600000` (10 minutes)   |
| `LMSTUDIO_WEBHOOK_TIMEOUT`             | Timeout for webhook calls in milliseconds                                  | `30000` (30 seconds)    |
| `NGINX_PORT`                           | Nginx HTTP port                                                            | `8080`                  |
| `NGINX_SSL_PORT`                       | Nginx HTTPS port                                                           | `8443`                  |
| `NGINX_PROXY_CONNECT_TIMEOUT`          | Nginx proxy connect timeout (seconds)                                      | `90`                    |
| `NGINX_PROXY_SEND_TIMEOUT`             | Nginx proxy send timeout (seconds)                                         | `330`                   |
| `NGINX_PROXY_READ_TIMEOUT`             | Nginx proxy read timeout (seconds)                                         | `330`                   |
| `NGROK_AUTHTOKEN`                      | Ngrok auth token                                                           | Required                |
| `NGROK_REGION`                         | Ngrok region                                                               | `us`                    |
| `AUTH_USERNAME`                        | API username                                                               | `admin`                 |
| `AUTH_PASSWORD`                        | API password                                                               | `secure_password_123`   |
| `RATE_LIMIT`                           | Rate limit                                                                 | `10r/s`                 |
| `RATE_BURST`                           | Rate limit burst                                                           | `20`                    |
| `VLLM_BRIDGE_ENABLED`                  | Enable optional VLLM bridge profile in `docker-compose`                    | `true`                  |
| `VLLM_BRIDGE_PORT`                     | VLLM bridge service port                                                   | `8000`                  |
| `VLLM_BRIDGE_CHAT_TIMEOUT`             | VLLM bridge chat completion timeout (seconds)                              | `300`                   |
| `VLLM_BRIDGE_MODELS_TIMEOUT`           | VLLM bridge models endpoint timeout (seconds)                              | `30`                    |
| `SSL_ENABLED`                          | Enable SSL termination in nginx                                            | `false`                 |
| `SSL_CERT_PATH`                        | Path to SSL certificate inside the container                               | `./certs/server.crt`    |
| `SSL_KEY_PATH`                         | Path to SSL private key inside the container                               | `./certs/server.key`    |



## Architecture

```
Internet → Ngrok → Docker Network → Nginx → Fastify Proxy → Local LM Studio
                                             ↓
                                       SQLite Logging
                                       Authentication
                                       Rate Limiting
                                       Security Headers
```

## API Usage

### Health Check (nginx)
```bash
curl http://localhost:8080/health
```

### OpenAI-compatible LM Studio endpoints

All LM Studio endpoints are exposed under `/v1/*` via nginx and the Fastify proxy.

**List models**
```bash
curl -u username:password "http://localhost:8080/v1/models"
```

**Non-streaming chat completion**
```bash
curl -u username:password \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama2",
    "messages": [
      {"role": "user", "content": "Hello, how are you?"}
    ],
    "stream": false
  }' \
  "http://localhost:8080/v1/chat/completions"
```

**Streaming chat completion**
```bash
curl -u username:password \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama2",
    "messages": [
      {"role": "user", "content": "Tell me a story"}
    ],
    "stream": true
  }' \
  "http://localhost:8080/v1/chat/completions"
```

## Security Features

- **Basic Authentication** - Username/password protection
- **Rate Limiting** - Configurable request limits
- **Security Headers** - XSS protection, content-type sniffing prevention
- **SSL/TLS Support** - Optional HTTPS with self-signed certificates
- **Request Size Limits** - Prevents large payload attacks
- **Access Logging** - Monitor and audit API usage

## Monitoring

### Service URLs
- **LM Studio local server**: `localhost:1234`
- **Ngrok Dashboard**: `http://localhost:4040`
- **Nginx health check**: `http://localhost:8080/health`
- **Fastify proxy health** (inside Docker): `curl http://localhost:3000/health` from the `lmstudio-fastify-proxy` container

### Get Public URL
```bash
curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url'
```

## Usage

### Get your ngrok URL:
```bash
curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url'
```

### Update Local environment: 
Set `ngrokUrl` to your tunnel URL in Bruno environments

### Test public access: 
Use the new ngrok examples with authentication

### View Logs
```bash
# All services
docker compose logs -f

# Specific services
docker compose logs -f nginx
docker compose logs -f lmstudio-fastify-proxy
docker compose logs -f ngrok

# Nginx access logs
tail -f logs/access.log
```

## Management Scripts & Make targets

From the project root:

- `./scripts/setup.sh` – Initial setup and configuration
- `./scripts/start.sh` – Start all services (LM Studio must already be running)
- `./scripts/stop.sh` – Stop Docker services
- `./scripts/test-api.sh` – Test API functionality

Or use the Makefile shortcuts:

- `make setup` – Run setup script
- `make start` – Start all services
- `make stop` – Stop all services
- `make status` – Show Docker status, LM Studio status, nginx health, and Fastify proxy health

## Troubleshooting

### Common Issues

1. **LM Studio not found**
   
   LM Studio must be installed manually from the official website:
   ```bash
   # Download and install from: https://lmstudio.ai/
   # 
   # For macOS: Download the .dmg file and drag to Applications folder
   # For Windows: Download and run the installer
   # For Linux: Download the AppImage or use the provided installation method
   ```
   
   After installation:
   1. Open LM Studio application
   2. Go to the "Local Server" tab
   3. Click "Start Server" to enable the API on port 1234
   4. Optionally load a model for testing

2. **Docker not running**
   ```bash
   # macOS
   open -a Docker
   
   # Linux
   sudo systemctl start docker
   ```

3. **Ngrok authentication failed**
   - Get your auth token from https://dashboard.ngrok.com
   - Update `NGROK_AUTHTOKEN` in `.env`

4. **Model not available**
   ```bash
   # Start LM Studio server on port 1234
   export LMSTUDIO_MODEL="your-preferred-model"
   ```

5. **Permission denied on scripts**
   ```bash
   chmod +x scripts/*.sh
   ```

### Logs and Debugging

- Check LM Studio: Verify server is running on port 1234
- Check Docker: `docker-compose ps`
- Check nginx config: `docker-compose exec nginx nginx -t`
- Check ngrok status: `curl http://localhost:4040/api/tunnels`

## Customization

### Adding Custom nginx Configuration
Edit `nginx/conf.d/default.conf` for custom routing or security rules.

### Changing Rate Limits
Update the `limit_req_zone` directives in `nginx/nginx.conf`.

### Adding IP Whitelisting
Add `allow` and `deny` directives in the nginx configuration.

### Custom SSL Certificates
Replace the self-signed certificates in the `certs/` directory.

## License

MIT License - feel free to modify and distribute.
