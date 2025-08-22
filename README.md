# LM Studio Nginx Ngrok Setup

This project provides a secure, authenticated proxy setup for LM Studio API access through nginx and ngrok.

- **LM Studio Integration** - Direct proxy to LM Studio's OpenAI-compatible API
- **Security** - Basic authentication, rate limiting, security headers  
- **Public Access** - Ngrok tunnel for external access
- **Monitoring** - Health checks and access logging
- **Containerized** - nginx and ngrok run in Docker, LM Studio runs locally
- **Easy Setup** - Automated setup and management scripts

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
   docker-compose up -d
   ```

4. **Test the API:**
   ```bash
   curl -u admin:secure_pass http://localhost:8080/api/tags
   ```

## LM Studio Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LMSTUDIO_MODEL` | LM Studio model to use | `your-model` |
| `LMSTUDIO_HOST` | LM Studio host | `localhost` |
| `LMSTUDIO_PORT` | LM Studio port | `1234` |
| `NGINX_PORT` | Nginx HTTP port | `8080` |
| `NGINX_SSL_PORT` | Nginx HTTPS port | `8443` |
| `NGROK_AUTHTOKEN` | Ngrok auth token | Required |
| `NGROK_REGION` | Ngrok region | `us` |
| `AUTH_USERNAME` | API username | `admin` |
| `AUTH_PASSWORD` | API password | `secure_password_123` |
| `RATE_LIMIT` | Rate limit | `10r/s` |
| `SSL_ENABLED` | Enable SSL | `false` |


## Architecture

```
Internet → Ngrok → Docker Network → Nginx → Local LM Studio
                                     ↓
                               Authentication
                               Rate Limiting
                               Security Headers
```

## API Usage

### Health Check
```bash
curl http://localhost:8080/health
```

### List Models
```bash
curl -u username:password http://localhost:8080/api/tags
```

### Generate Response
```bash
curl -u username:password http://localhost:8080/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama2",
    "prompt": "Hello, how are you?",
    "stream": false
  }'
```

### Streaming Response
```bash
curl -u username:password http://localhost:8080/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama2",
    "prompt": "Tell me a story",
    "stream": true
  }'
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
- **Accessible**: Available on `localhost:1234`
- **Ngrok Dashboard**: `http://localhost:4040`
- **Health Check**: `http://localhost:8080/health`

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
docker-compose logs -f

# Specific service
docker-compose logs -f nginx
docker-compose logs -f ngrok

# Nginx access logs
tail -f logs/access.log
```

## Management Scripts

- `./setup.sh` - Initial setup and configuration
- `./start.sh` - Start all services
- `./stop.sh` - Stop Docker services
- `./test-api.sh` - Test API functionality

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
