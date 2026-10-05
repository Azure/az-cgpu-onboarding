# syntax=docker/dockerfile:1

# Official Rust image on supported Debian 12 Bookworm, pinned for reproducibility.
FROM rust:1.98.1-slim-bookworm@sha256:ebd900bae66fd508b466cef82d64a83a5fb34682e4c8b2797a42908bddc95a57 AS builder

ARG VERIFIER_REPO_URL=https://github.com/NVIDIA/attestation-sdk
ARG VERIFIER_REPO_BRANCH=main
ARG NVAT_BUILD_JOBS=2

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        cmake build-essential pkg-config git curl ca-certificates perl patch \
        autoconf automake libtool zlib1g-dev libssl-dev \
        libcurl4-openssl-dev libxml2-dev libxmlsec1-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --quiet --depth 1 --branch "${VERIFIER_REPO_BRANCH}" \
    "${VERIFIER_REPO_URL}" attestation-sdk

COPY attestation-sdk-ocsp-sha384.patch /tmp/attestation-sdk-ocsp-sha384.patch
RUN patch --batch --forward -d /src/attestation-sdk -p1 \
    < /tmp/attestation-sdk-ocsp-sha384.patch

RUN cmake \
        -S /src/attestation-sdk/nv-attestation-cli \
        -B /tmp/nvattest-build \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF \
        -DUSE_SYSTEM_NVAT=OFF \
        -DUSE_SYSTEM_DEPS=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_CXX_FLAGS="-Wno-error=stringop-overflow -Wno-error=pedantic" \
        -DCMAKE_SKIP_INSTALL_RULES=ON \
    && cmake --build /tmp/nvattest-build \
        --target nvattest --parallel "${NVAT_BUILD_JOBS}" \
    && binary="$(find /tmp/nvattest-build -name nvattest -type f | head -1)" \
    && test -n "${binary}" \
    && max_glibc="$(readelf --version-info "${binary}" \
        | grep -oE 'GLIBC_[0-9]+(\.[0-9]+)*' | sort -Vu | tail -1)" \
    && test -n "${max_glibc}" \
    && test "$(printf '%s\n' GLIBC_2.35 "${max_glibc}" | sort -V | tail -1)" = "GLIBC_2.35" \
    && install -D -m 0755 "${binary}" /artifacts/nvattest

# Export only the verifier; no toolchain or source is retained.
FROM scratch AS artifacts
COPY --from=builder /artifacts/nvattest /nvattest
