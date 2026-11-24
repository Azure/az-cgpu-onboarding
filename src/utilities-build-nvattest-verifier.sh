#!/usr/bin/env bash
#
# Build NVIDIA's nvattest verifier, used in step 2:
#   1. Detect Ubuntu's version and build in the corresponding Rust container.
#   2. Export only the verifier binary.
#   3. Remove the build images.
#
# Usage:
#   sudo bash utilities-build-nvattest-verifier.sh [output_dir]   # Default: this script's folder

set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER_FILES_DIR="$SCRIPT_DIR/nv_attest_gpu_verifier"
VERIFIER_REPO_URL="https://github.com/NVIDIA/attestation-sdk"
VERIFIER_REPO_BRANCH="release/2026.10.02"
WORK_DIR="${1:-$SCRIPT_DIR}"
OUT_BIN="$WORK_DIR/nvattest"
BUILD_LOG="$WORK_DIR/build.log"
NVAT_DOCKERFILE=""
if [ -z "${NVAT_BUILD_JOBS:-}" ]; then
    NVAT_BUILD_JOBS=$(( $(nproc) - 1 ))
    if [ "$NVAT_BUILD_JOBS" -lt 1 ]; then
        NVAT_BUILD_JOBS=1
    fi
fi

# Parse parameters.
NVAT_BUILD_IMAGE=""
if [ "$#" -gt 1 ] || [[ "${1:-}" == -* ]]; then
    echo "Usage: sudo bash utilities-build-nvattest-verifier.sh [output_dir]" >&2
    exit 1
fi

detect_ubuntu_version() {
    (
        . /etc/os-release
        if [ "${ID:-}" = ubuntu ]; then printf '%s\n' "$VERSION_ID"; fi
    )
}

configure_build_image() {
    NVAT_TARGET_UBUNTU="$(detect_ubuntu_version)"
    case "$NVAT_TARGET_UBUNTU" in
        22.04)
            NVAT_DOCKERFILE="$VERIFIER_FILES_DIR/Dockerfile.bullseye"
            ;;
        24.04)
            NVAT_DOCKERFILE="$VERIFIER_FILES_DIR/Dockerfile.azlinux3"
            ;;
        *) echo "ERROR: Builds support Ubuntu 22.04 or 24.04 only." >&2; return 1 ;;
    esac
    if [ ! -f "$NVAT_DOCKERFILE" ]; then
        echo "ERROR: Required Dockerfile not found: $NVAT_DOCKERFILE" >&2
        return 1
    fi
    # The selected Dockerfile is the single source of truth for its base image.
    NVAT_BUILD_IMAGE="$(awk 'toupper($1) == "FROM" { sub(/\r$/, "", $2); print $2; exit }' "$NVAT_DOCKERFILE")" || return 1
    if ! [[ "$NVAT_BUILD_IMAGE" =~ ^mcr\.microsoft\.com/[^[:space:]\$]+@sha256:[[:xdigit:]]{64}$ ]]; then
        echo "ERROR: Dockerfile must specify a literal, digest-pinned MCR base image: $NVAT_DOCKERFILE" >&2
        return 1
    fi
}

build_verifier() {
    echo "============================================================"
    echo "  Cloning and building nvattest in a Rust container"
    echo "============================================================"

    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: Docker is required. Run step-2-attestation.sh --gpu-only first." >&2
        return 1
    fi
    if ! [[ "$NVAT_BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: NVAT_BUILD_JOBS must be a positive integer." >&2
        return 1
    fi
    configure_build_image || return 1
    echo "This can take several minutes; failed downloads and builds are retried."
    sudo mkdir -p "$WORK_DIR" || return 1
    echo "Detected Ubuntu $NVAT_TARGET_UBUNTU; using its configured Rust build image."

    local build_context build_image build_container staged_bin
    local build_rc=0 export_rc=0
    build_context="$(mktemp -d /tmp/nvattest-context_XXXXXX)" || return 1
    build_image="nvattest-builder:$$"
    build_container="nvattest-export-$$"
    staged_bin="$WORK_DIR/.nvattest-new-$$"
    if ! cp "$NVAT_DOCKERFILE" "$build_context/Dockerfile"; then
        rm -rf "$build_context"
        return 1
    fi

    echo "Pulling build image: $NVAT_BUILD_IMAGE"
    if ! (
        for attempt in 1 2 3; do
            sudo docker pull --quiet "$NVAT_BUILD_IMAGE" && exit 0
            [ "$attempt" -lt 3 ] || exit 1
            sleep 10
        done
    ) 2>&1 | tee "$BUILD_LOG"; then
        rm -rf "$build_context"
        return 1
    fi

    sudo docker build --progress=plain --no-cache --force-rm \
        --build-arg VERIFIER_REPO_URL="$VERIFIER_REPO_URL" \
        --build-arg VERIFIER_REPO_BRANCH="$VERIFIER_REPO_BRANCH" \
        --build-arg NVAT_BUILD_JOBS="$NVAT_BUILD_JOBS" \
        --tag "$build_image" "$build_context" >"$BUILD_LOG" 2>&1 || build_rc=$?

    if [ "$build_rc" -eq 0 ]; then
        {
            sudo docker create --name "$build_container" "$build_image" /bin/true &&
            sudo docker cp "$build_container:/nvattest" "$staged_bin" &&
            sudo chmod 0755 "$staged_bin" &&
            sudo mv -f "$staged_bin" "$OUT_BIN"
        } >>"$BUILD_LOG" 2>&1 || export_rc=$?
    fi

    echo "Removing temporary build resources..."
    sudo docker rm -f "$build_container" >/dev/null 2>&1 || true
    sudo docker image rm "$build_image" >/dev/null 2>&1 || true
    sudo docker image rm "$NVAT_BUILD_IMAGE" >/dev/null 2>&1 || true
    sudo rm -f "$staged_bin"
    rm -rf "$build_context"

    if [ "$build_rc" -ne 0 ]; then
        echo "ERROR: nvattest build failed. Details: $BUILD_LOG" >&2
        grep -m 5 -B 2 -A 8 -Ei 'CMake Error|error:|Bad signature|failed to verify signature' "$BUILD_LOG" >&2 || true
        tail -50 "$BUILD_LOG" >&2
        return 1
    fi
    if [ "$export_rc" -ne 0 ]; then
        echo "ERROR: Failed to export nvattest build artifacts. Details: $BUILD_LOG" >&2
        return 1
    fi
    if [ ! -x "$OUT_BIN" ]; then
        echo "ERROR: Build completed without producing $OUT_BIN." >&2
        return 1
    fi

    echo "nvattest built successfully."
}

build_verifier
