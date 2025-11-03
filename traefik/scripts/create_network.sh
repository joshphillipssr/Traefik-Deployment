#!/usr/bin/env bash
set -euo pipefail

NETWORK_NAME="${NETWORK_NAME:-traefik_proxy}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker command not found. Please install Docker."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker daemon is not reachable. Please start Docker."
  exit 1
fi

echo "Ensuring Docker network '${NETWORK_NAME}' exists..."

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Network '${NETWORK_NAME}' already exists."
else
  docker network create "${NETWORK_NAME}" >/dev/null
  echo "✅ Created network '${NETWORK_NAME}'."
fi