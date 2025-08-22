# Request Flow Diagram

## Architecture Overview

```mermaid
graph TB
    subgraph "External Access"
        Client[Client/Bruno]
        Browser[Web Browser]
    end
    
    subgraph "Public Internet"
        Ngrok[Ngrok Tunnel<br/>https://34bcf1494c22.ngrok-free.app]
    end
    
    subgraph "Docker Network"
        direction TB
        NginxProxy[Nginx Proxy<br/>:80, :443<br/>Auth + Rate Limiting]
        LM StudioService[LM Studio Service<br/>:11434<br/>LLM Processing]
        VLLMBridge[VLLM Bridge<br/>:8000<br/>API Translation]
    end
    
    subgraph "Host System"
        LM StudioHost[LM Studio Server<br/>0.0.0.0:11434]
    end
    
    %% Request Flow - Direct Local
    Client -->|HTTP/HTTPS<br/>localhost:8080/8443| NginxProxy
    
    %% Request Flow - Public via Ngrok
    Client -->|HTTPS + ngrok-skip-browser-warning| Ngrok
    Ngrok -->|Forward to nginx:80| NginxProxy
    
    %% Internal Processing
    NginxProxy -->|Basic Auth<br/>admin:secure_password_123| NginxProxy
    NginxProxy -->|Proxy Pass<br/>5min timeout| LM StudioHost
    
    %% VLLM Bridge Flow
    Client -->|VLLM API<br/>localhost:8000| VLLMBridge
    VLLMBridge -->|Translate & Forward| LM StudioHost
    
    %% Health Check
    Browser -->|GET /health<br/>+ Auth| NginxProxy
    NginxProxy -->|200 OK + timestamp| Browser
    
    %% Styling
    classDef external fill:#e1f5fe
    classDef public fill:#f3e5f5
    classDef docker fill:#e8f5e8
    classDef host fill:#fff3e0
    
    class Client,Browser external
    class Ngrok public
    class NginxProxy,LM StudioService,VLLMBridge docker
    class LM StudioHost host
```

## Request Types

### 1. Direct Local Access
```mermaid
sequenceDiagram
    participant C as Client
    participant N as Nginx Proxy
    participant O as LM Studio Host
    
    C->>N: POST /api/generate + Basic Auth
    N->>N: Validate Credentials
    N->>N: Apply Rate Limiting
    N->>O: Forward Request (5min timeout)
    O->>O: Process LLM Request
    O->>N: Return Response
    N->>C: JSON Response
```

### 2. Public Ngrok Access
```mermaid
sequenceDiagram
    participant C as Client
    participant NG as Ngrok Tunnel
    participant N as Nginx Proxy
    participant O as LM Studio Host
    
    C->>NG: HTTPS + ngrok-skip-browser-warning
    NG->>N: Forward to nginx:80
    N->>N: Validate Basic Auth
    N->>N: Apply Security Headers
    N->>O: Proxy to host.docker.internal:11434
    O->>O: Generate Response
    O->>N: Return JSON
    N->>NG: Add Security Headers
    NG->>C: HTTPS Response
```

### 3. VLLM Bridge Access
```mermaid
sequenceDiagram
    participant C as Client
    participant V as VLLM Bridge
    participant O as LM Studio Host
    
    C->>V: POST /v1/chat/completions
    V->>V: Translate VLLM → LM Studio Format
    V->>O: POST /api/chat
    O->>O: Process Request
    O->>V: LM Studio Response
    V->>V: Translate LM Studio → VLLM Format
    V->>C: VLLM-Compatible Response
```

## Security Layers

```mermaid
graph LR
    subgraph "Security Stack"
        A[Rate Limiting<br/>10req/s API<br/>30req/s Health] 
        B[Basic Auth<br/>admin:secure_password_123]
        C[Security Headers<br/>XSS, CSRF, CSP]
        D[SSL/TLS<br/>TLS 1.2/1.3]
        E[Attack Prevention<br/>Block .env, .git, etc]
    end
    
    Request --> A --> B --> C --> D --> E --> Backend
    
    classDef security fill:#ffebee
    class A,B,C,D,E security
```

## Timeout Configuration

| Component | Connect | Send | Read | Total |
|-----------|---------|------|------|-------|
| Client Body | - | - | - | 300s |
| Client Header | - | - | - | 60s |
| Proxy Connect | 60s | - | - | - |
| Proxy Send | - | 300s | - | - |
| Proxy Read | - | - | 300s | - |
| Keepalive | - | - | - | 300s |

*All timeouts optimized for LLM processing (5-minute max)*
