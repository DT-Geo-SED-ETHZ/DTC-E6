#!/usr/bin/env bash
# =============================================================================================
# SeisComP Docker Build Script
# =============================================================================================
#
# This script builds a Docker image for the SeisComP project using Docker's build or buildx
# commands. It detects the host OS and architecture to determine if buildx is needed,
# especially for Apple Silicon Macs requiring cross-platform builds.
#
# Usage:
#   ./docker_build.sh
#
# Environment Variables:
#   DOCKERFILE       Path to the Dockerfile to use (default: Dockerfile.dtgeo)
#   IMAGE_TAG        Tag to assign to the built image (default: dtgeofinder:master)
#   BUILD_CONTEXT    Directory to use as build context (default: current directory)
#   FORCE_BUILDX     If set to "true", forces usage of docker buildx even if not needed
#   FORCE_PLATFORM   Specify platform to build for (e.g., linux/amd64, linux/arm64)
#
# Examples:
#   # Build with defaults
#   ./docker_build.sh
#
#   # Build specifying a different Dockerfile and image tag
#   DOCKERFILE=Dockerfile.custom IMAGE_TAG=myimage:latest ./docker_build.sh
#
#   # Force buildx usage on native platform
#   FORCE_BUILDX=true ./docker_build.sh
#
#   # Force build for specific platform
#   FORCE_PLATFORM=linux/amd64 ./docker_build.sh
#
# Notes:
#   - On macOS with Apple Silicon (arm64), the script automatically uses buildx with
#     platform linux/amd64 to ensure compatibility.
#   - The script requires Docker to be installed and accessible via PATH.
#   - If buildx is needed but not available, the script will exit with an error.
#
# =============================================================================================
# This was the command line used for Mac OS on Silicon chip on my laptop
# docker buildx build --platform linux/amd64 -f Dockerfile.dtgeo -t dtgeofinder:master --load .
# =============================================================================================
set -Eeuo pipefail

# Configurables (env-overridable)
DOCKERFILE=${DOCKERFILE:-Dockerfile.dtgeo}
IMAGE_TAG=${IMAGE_TAG:-dtgeofinder:master}
BUILD_CONTEXT=${BUILD_CONTEXT:-.}

# Helper: print info
info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR]\033[0m %s\n" "$*"; }

# Ensure Docker is available
if ! command -v docker >/dev/null 2>&1; then
  err "Docker is not installed or not on PATH."; exit 127
fi

# Detect host OS/arch
OS=$(uname -s 2>/dev/null || echo unknown)
ARCH=$(uname -m 2>/dev/null || echo unknown)

# Determine whether we must use buildx (e.g., Apple Silicon needs linux/amd64)
NEED_BUILDX=false
PLATFORM_ARG=""

# Auto-detect common case: macOS on Apple Silicon
if [[ "$OS" == "Darwin" && "$ARCH" == "arm64" ]]; then
  NEED_BUILDX=true
  PLATFORM_ARG="--platform linux/amd64"
  info "Detected macOS arm64: will use buildx with ${PLATFORM_ARG}."
fi

# Allow users to force behavior via env flags
#   FORCE_BUILDX=true     -> force buildx even if not strictly needed
#   FORCE_PLATFORM=...    -> e.g. linux/amd64 or linux/arm64
if [[ "${FORCE_PLATFORM:-}" != "" ]]; then
  PLATFORM_ARG="--platform ${FORCE_PLATFORM}"
  NEED_BUILDX=true
  info "FORCE_PLATFORM set: will use buildx with ${PLATFORM_ARG}."
fi
if [[ "${FORCE_BUILDX:-}" == "true" ]]; then
  NEED_BUILDX=true
  info "FORCE_BUILDX=true: will use buildx."
fi

# Check if buildx is available when needed
if $NEED_BUILDX; then
  if ! docker buildx version >/dev/null 2>&1; then
    err "docker buildx is required but not available. Install Docker Buildx or run without NEED_BUILDX."; exit 1
  fi
  # Build with buildx, loading the image into the local Docker engine by default
  info "Building with: docker buildx build ${PLATFORM_ARG} -f ${DOCKERFILE} -t ${IMAGE_TAG} --load ${BUILD_CONTEXT}"
  docker buildx build ${PLATFORM_ARG} -f "${DOCKERFILE}" -t "${IMAGE_TAG}" --load "${BUILD_CONTEXT}"
else
  # Standard docker build on native platform
  info "Building with: docker build -f ${DOCKERFILE} -t ${IMAGE_TAG} ${BUILD_CONTEXT}"
  docker build -f "${DOCKERFILE}" -t "${IMAGE_TAG}" "${BUILD_CONTEXT}"
fi

info "Build complete: ${IMAGE_TAG}"