# DisableDockerDetector "Not build in ADO pipeline"
FROM golang:1.23 AS builder

WORKDIR /app

# Copy entire source code (including ./cmd, ./internal, etc.)
COPY . .

# Always create go.mod and go.sum on the fly
RUN go mod init local_gpu_verifier_http_service \
    && go mod tidy

# Build the binary
ARG ENABLE_DEBUG_LOGGING=false
RUN if [ "$ENABLE_DEBUG_LOGGING" = "true" ]; then \
        go build -ldflags="-X main.enableDebugLogging=true" -o /app/bin/local-gpu-attestation-http-service ./cmd/local_gpu_verifier_http_service; \
    else \
        go build -o /app/bin/local-gpu-attestation-http-service ./cmd/local_gpu_verifier_http_service; \
    fi