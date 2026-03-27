# Local GPU Verifier HTTP Service

An HTTP service that exposes GPU attestation as a REST API. It wraps the local GPU verifier Python module (`verifier.cc_admin`) and serves attestation results over HTTP and a Unix domain socket.

## Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/gpu_attest` | GET, POST | Run GPU attestation. Optionally accepts a `nonce` parameter (32-byte hex string). |
| `/heartbeat` | GET | Returns `200 OK` if the service is running. |

### Nonce Parameter

- **GET**: pass as query parameter — `?nonce=<64-char hex string>`
- **POST**: pass as JSON body — `{"nonce": "<64-char hex string>"}`

The nonce must be a valid hex string representing exactly 32 bytes (64 hex characters).

### Response Format

```json
{
  "attestation_output": "<raw output from cc_admin>",
  "entity_attestation_token": { ... }
}
```

- `200` — attestation succeeded
- `400` — attestation ran but failed, or invalid request
- `500` — error executing the attestation command

## Configuration

The service binary accepts the following flags:

| Flag | Default | Description |
|---|---|---|
| `-port` | `8123` | HTTP listen port |
| `-socket` | `/var/run/gpu-attestation/gpu-attestation.sock` | Unix socket path |
| `-verifierroot` | `/usr/local/lib/local_gpu_verifier` | Root directory of the GPU verifier Python environment |
| `-logpath` | `/usr/local/bin/local_gpu_verifier_http_service/attestation_service.log` | Log file path (with rotation) |
| `-successstr` | `GPU Attestation is Successful` | String to match for successful attestation |
| `-heartbeatreport` | `true` | Enable periodic heartbeat self-check logging |
| `-heartbeatinterval` | `15` | Heartbeat interval in minutes |

## Installation via Onboarding Script

During VM onboarding, the service is installed automatically when the `--enable-gpu-verifier-service` flag (bash) or `-enablegpuverifierservice $true` (PowerShell) is passed to the onboarding script. This runs the utility script [`utilities-install-local-gpu-verfier-service.sh`](../utilities-install-local-gpu-verfier-service.sh), which extracts the pre-built service tarball, calls `install.sh --enable-service`, and runs a smoke test against both the HTTP and Unix socket endpoints.

To install manually on a VM that was onboarded without the flag:

```bash
cd cgpu-onboarding-package
sudo bash utilities-install-local-gpu-verfier-service.sh
```

## Building

The service is built inside a Docker container using Go 1.26.1. The `install.sh` script handles the full workflow:

```bash
cd local_gpu_verifier_http_service
sudo bash ./install.sh [--enable-service] [--enable-debug-log]
```

| Option | Description |
|---|---|
| `--enable-service` | Install the systemd unit and start the service |
| `--enable-debug-log` | Compile with debug-level logging enabled |

The build produces a single binary named `local-gpu-attestation-http-service` located at `bin/local-gpu-attestation-http-service`, which is copied to `/usr/local/bin/local_gpu_verifier_http_service/`. The systemd unit executes this binary.

## Systemd Service

When installed with `--enable-service`, the service runs as `local-gpu-attestation.service`:

```bash
# Check status
sudo systemctl status local-gpu-attestation

# View logs
sudo journalctl -u local-gpu-attestation
```

The service requires `nvidia-persistenced.service` and restarts automatically on failure.

## Testing

After the service is running, you can test both interfaces:

```bash
# HTTP
nonce=$(openssl rand -hex 32)
curl -s "http://localhost:8123/gpu_attest?nonce=$nonce" | jq .

# Unix socket
curl -s --unix-socket /var/run/gpu-attestation/gpu-attestation.sock \
  "http://localhost/gpu_attest?nonce=$nonce" | jq .

# Heartbeat
curl -s http://localhost:8123/heartbeat
```

## Project Structure

```
local_gpu_verifier_http_service/
├── cmd/local_gpu_verifier_http_service/
│   └── main.go              # Service entry point and HTTP handlers
├── Dockerfile                # Multi-stage Go build
├── install.sh                # Build + install + systemd setup
├── local-gpu-attestation.service  # systemd unit file
└── .gitignore
```
