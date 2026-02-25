# API Testing with Bruno

This Bruno collection provides API testing for the vLLM nginx proxy setup.

## Structure

```
bruno/
├── environments/           # Environment configurations
│   ├── Local.bru          # Local development settings
│   └── Production.bru     # Production / RunPod settings
├── api/                   # API endpoints
│   ├── folder.bru
│   ├── Chat Completions.bru
│   ├── Chat Completions (with schema).bru
│   └── List Models.bru
├── Authentication Test.bru # Auth test
├── Health Check.bru        # Health check
├── bruno.json
└── README.md
```

## Getting Started

1. **Install Bruno**: Download from [usebruno.com](https://www.usebruno.com/)
2. **Open Collection**: Open this `bruno/` folder in Bruno
3. **Select Environment**: "Local" for local dev, "Production" for RunPod/remote
4. **Start services**:
   ```bash
   cd ../
   docker compose -f docker-compose.yml -f docker-compose.local.yml up --build -d
   ```

## Environment Variables

### Local
- `base_url`: `http://localhost:8080`
- `auth_username`: `admin`
- `auth_password`: your password
- `fastify_url`: `http://localhost:3000`

### Production
- `base_url`: Your RunPod or production domain (HTTPS provided by RunPod)
- `auth_username` / `auth_password`: Production credentials

## API Endpoints

- **Health Check**: `GET /health` — no auth required
- **List Models**: `GET /v1/models`
- **Chat Completions**: `POST /v1/chat/completions`
- **Chat Completions (with schema)**: Structured JSON output

## Troubleshooting

1. **Connection refused** — ensure services are running: `docker compose ps`
2. **Authentication failed** — check `auth_username` / `auth_password` in environment
3. **Model not found** — verify `VLLM_MODEL` matches a loaded model

```bash
# Check service status
docker compose ps

# View logs
docker compose logs -f

# Quick health check
curl -u admin:password http://localhost:8080/health
```
