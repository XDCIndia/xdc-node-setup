# API Documentation

This directory contains the API documentation for the XDC Node Dashboard.

## OpenAPI Specification

The API is documented using OpenAPI 3.0.3 specification in `openapi.yaml`.

### Viewing the Documentation

You can view the interactive API documentation using Swagger UI:

```bash
# Using Docker
docker run -p 8080:8080 -e SWAGGER_JSON=/api/openapi.yaml -v $(pwd)/openapi.yaml:/api/openapi.yaml swaggerapi/swagger-ui

# Then open http://localhost:8080 in your browser
```

Or using Redoc:

```bash
# Using Docker
docker run -p 8080:80 -e SPEC_URL=/api/openapi.yaml -v $(pwd)/openapi.yaml:/usr/share/nginx/html/api/openapi.yaml redocly/redoc

# Then open http://localhost:8080 in your browser
```

### Generating Client Libraries

You can generate client libraries from the OpenAPI spec:

```bash
# Generate TypeScript client
npx openapi-typescript-codegen --input openapi.yaml --output ./client --client fetch

# Generate Python client
openapi-generator-cli generate -i openapi.yaml -g python -o ./python-client

# Generate Go client
openapi-generator-cli generate -i openapi.yaml -g go -o ./go-client
```

## API Endpoints Overview

### Health Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/health/live` | GET | No | Liveness probe |
| `/health/ready` | GET | No | Readiness probe |
| `/health/deep` | GET | Yes | Deep health check |

### Metrics Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/metrics` | GET | Yes | Node metrics (JSON) |
| `/metrics/prometheus` | GET | No | Prometheus metrics |

### Node Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/node/status` | GET | Yes | Node status |
| `/node/block-height` | GET | Yes | Current block height |
| `/node/sync-status` | GET | Yes | Sync status |

### Peer Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/peers` | GET | Yes | List peers |
| `/peers/count` | GET | Yes | Peer count |

### Backup Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/backup/create` | POST | Yes | Create backup |
| `/backup/{id}/status` | GET | Yes | Backup status |
| `/backup/list` | GET | Yes | List backups |

### Configuration Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/config` | GET | Yes | Get configuration |
| `/config` | PUT | Yes | Update configuration |

## Authentication

The API supports two authentication methods:

### API Key

Include your API key in the `X-API-Key` header:

```bash
curl -H "X-API-Key: your-api-key" https://api.xdc-node.local/api/node/status
```

### JWT Bearer Token

Include your JWT token in the Authorization header:

```bash
curl -H "Authorization: Bearer your-jwt-token" https://api.xdc-node.local/api/node/status
```

## Rate Limiting

API requests are rate limited to:

- 100 requests per minute for read operations
- 10 requests per minute for write operations

Rate limit headers are included in all responses:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1707811200
```

## Error Handling

All errors follow a consistent format:

```json
{
  "error": "Human-readable error message",
  "code": "ERROR_CODE",
  "details": {},
  "timestamp": "2026-02-13T10:00:00Z"
}
```

Common error codes:

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `UNAUTHORIZED` | 401 | Invalid or missing API key |
| `FORBIDDEN` | 403 | Valid API key but insufficient permissions |
| `NOT_FOUND` | 404 | Resource not found |
| `VALIDATION_ERROR` | 400 | Invalid request parameters |
| `INTERNAL_ERROR` | 500 | Internal server error |
| `SERVICE_UNAVAILABLE` | 503 | Service temporarily unavailable |

## WebSocket Support

Real-time updates are available via WebSocket at:

```
ws://localhost:3000/api/ws
```

Subscribe to events:

```json
{
  "action": "subscribe",
  "channels": ["blocks", "peers", "sync"]
}
```

## SDK Examples

### JavaScript/TypeScript

```typescript
import { XdcNodeClient } from './client';

const client = new XdcNodeClient({
  baseUrl: 'http://localhost:3000/api',
  apiKey: 'your-api-key'
});

// Get node status
const status = await client.node.getStatus();
console.log(`Block height: ${status.blockHeight}`);

// Create backup
const backup = await client.backup.create({
  type: 'full',
  encrypt: true
});
```

### Python

```python
from xdc_node_client import XdcNodeClient

client = XdcNodeClient(
    base_url='http://localhost:3000/api',
    api_key='your-api-key'
)

# Get node status
status = client.node.get_status()
print(f"Block height: {status['blockHeight']}")

# Create backup
backup = client.backup.create(type='full', encrypt=True)
```

### Go

```go
package main

import (
    "context"
    "fmt"
    "log"
    
    xdc "github.com/xdc/client"
)

func main() {
    client := xdc.NewClient("http://localhost:3000/api")
    client.SetAPIKey("your-api-key")
    
    status, err := client.Node.GetStatus(context.Background())
    if err != nil {
        log.Fatal(err)
    }
    
    fmt.Printf("Block height: %d\n", status.BlockHeight)
}
```