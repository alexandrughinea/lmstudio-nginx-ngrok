# LM Studio API Testing with Bruno

This Bruno collection provides comprehensive API testing for the LM Studio nginx proxy setup.

## Structure

```
bruno/
├── environments/           # Environment configurations
│   ├── Local.bru          # Local development settings
│   └── Production.bru     # Production settings
├── lmstudio/              # LM Studio API endpoints
│   ├── folder.bru         # Collection metadata
│   ├── LM Studio Chat Completions.bru
│   ├── LM Studio Chat Completions (with schema).bru
│   └── LM Studio List Models.bru
├── ngrok/                 # Public ngrok tunnel endpoints
│   ├── folder.bru         # Collection metadata
│   ├── ngrok LM Studio Chat Completions.bru
│   ├── ngrok LM Studio Chat Completions (with schema).bru
│   ├── ngrok Authentication Test.bru
│   ├── ngrok Health Check.bru
│   └── ngrok LM Studio List Models.bru
├── Authentication Test.bru # Local auth test
├── Health Check.bru       # Local health check
├── bruno.json            # Bruno configuration
└── README.md             # This file
```

## Getting Started

1. **Install Bruno**: Download from [bruno.sh](https://www.usebruno.com/)

2. **Open Collection**: Open this `bruno/` folder in Bruno

3. **Configure Environment**: 
   - Select "Local" environment for local testing
   - Update `ngrok_url` variable after starting services

4. **Start Services**:
   ```bash
   cd ../
   ./start.sh
   ```

5. **Get ngrok URL**:
   ```bash
   curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url'
   ```

## Environment Variables

### Local Environment
- `base_url`: `http://localhost:8080` - Local nginx proxy
- `ngrok_url`: Your ngrok tunnel URL
- `auth_username`: `admin` - Basic auth username
- `auth_password`: `secure_password_123` - Basic auth password
- `lmstudio_model`: `gemma3:27b` - LM Studio model name

### Production Environment
- `base_url`: Your production domain
- `ngrok_url`: Your production ngrok URL
- `auth_username`: Production username
- `auth_password`: Production password
- `lmstudio_model`: Production model name

## API Endpoints

### LM Studio Collection (`/lmstudio/`)
Direct access to LM Studio through the nginx proxy:

- **Chat Completions**: Standard OpenAI-compatible chat
- **Chat Completions (with schema)**: Structured output with JSON schema
- **List Models**: Available models in LM Studio

### ngrok Collection (`/ngrok/`)
Public access through ngrok tunnel:

- **Chat Completions**: Public chat endpoint
- **Chat Completions (with schema)**: Public structured output
- **Authentication Test**: Test auth through tunnel
- **Health Check**: Service status through tunnel
- **List Models**: Available models through tunnel

### Root Collection
Basic service endpoints:

- **Authentication Test**: Test local auth
- **Health Check**: Local service status

## Features Tested

### Structured Outputs
LM Studio provides superior structured output quality through:
- **GGUF models**: Grammar-based sampling via llama.cpp
- **MLX models**: Constrained generation via Outlines library
- **Schema enforcement**: Guaranteed JSON compliance at inference level

### Authentication
- Basic HTTP authentication on all protected endpoints
- Health check endpoint accessible without auth

### Error Handling
- Proper error responses for invalid requests
- Authentication failures
- Model not found errors

## Usage Tips

1. **Start with Health Check**: Always test the health endpoint first
2. **Verify Authentication**: Use the auth test before API calls
3. **Test Locally First**: Use local endpoints before ngrok
4. **Monitor Logs**: Check Docker logs for debugging
5. **Update ngrok URL**: Remember to update the ngrok_url variable

## Troubleshooting

### Common Issues

1. **Connection refused**: Ensure services are running (`./start.sh`)
2. **Authentication failed**: Check username/password in environment
3. **Model not found**: Verify model is loaded in LM Studio
4. **ngrok tunnel down**: Restart services or check ngrok dashboard

### Debugging Commands

```bash
# Check service status
docker-compose ps

# View logs
docker-compose logs -f

# Test local connectivity
curl -u admin:secure_password_123 http://localhost:8080/health

# Get ngrok status
curl http://localhost:4040/api/tunnels
```
