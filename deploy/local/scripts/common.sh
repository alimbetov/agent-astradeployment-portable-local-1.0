#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${LOCAL_DIR}/docker-compose.astravector.yml"
ENV_FILE="${LOCAL_DIR}/.env"
NETWORK_NAME="astradeployment-network"

compose() {
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

env_value() {
  local key="$1"
  local line
  line="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 || true)"
  printf '%s' "${line#*=}"
}

require_env_value() {
  local key="$1"
  local value
  value="$(env_value "$key")"
  if [ -z "$value" ]; then
    echo "ERROR: ${key} is empty in ${ENV_FILE}" >&2
    exit 1
  fi
}

helper_curl() {
  docker run --rm --network "${NETWORK_NAME}" curlimages/curl:8.10.1 "$@"
}

helper_grpcurl() {
  docker run --rm -i --network "${NETWORK_NAME}" fullstorydev/grpcurl:v1.9.3 "$@"
}
