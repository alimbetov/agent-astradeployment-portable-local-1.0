#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

require_cmd docker
[ -f "${ENV_FILE}" ] || {
  echo "ERROR: ${ENV_FILE} is missing. Copy .env.example to .env and fill secrets." >&2
  exit 1
}

docker info >/dev/null 2>&1 || {
  echo "ERROR: Docker daemon is not reachable" >&2
  exit 1
}
docker compose version >/dev/null

require_env_value POSTGRES_PASSWORD
require_env_value ASTRAVECTOR_DB_URL
require_env_value ASTRAVECTOR_NEXUS_USERNAME
require_env_value ASTRAVECTOR_NEXUS_PASSWORD
require_env_value ASTRAVECTOR_IMAGE
require_env_value ASTRAVECTOR_EXPECTED_DIGEST

compose config >/dev/null

arch="$(uname -m)"
allow_unverified="$(env_value ASTRADEPLOYMENT_ALLOW_UNVERIFIED_ARCH)"
if [ "$arch" != "arm64" ] && [ "$arch" != "aarch64" ] && [ "${allow_unverified:-false}" != "true" ]; then
  echo "ERROR: current validated AstraVector baseline is linux/arm64; host is ${arch}." >&2
  echo "Publish/choose a matching image or explicitly set ASTRADEPLOYMENT_ALLOW_UNVERIFIED_ARCH=true for a controlled test." >&2
  exit 1
fi

free_kb="$(df -Pk "${LOCAL_DIR}" | awk 'NR==2 {print $4}')"
free_gib=$((free_kb / 1024 / 1024))
if docker volume inspect astradeployment-model-cache >/dev/null 2>&1; then
  threshold=6
  model_state="existing"
else
  threshold=12
  model_state="absent"
fi

printf 'Docker: ready\nArchitecture: %s\nFree disk: %s GiB\nModel cache: %s\n' "$arch" "$free_gib" "$model_state"
if [ "$free_gib" -lt "$threshold" ]; then
  echo "ERROR: insufficient free disk. Need at least ${threshold} GiB for this path." >&2
  exit 1
fi

image="$(env_value ASTRAVECTOR_IMAGE)"
if docker image inspect "$image" >/dev/null 2>&1; then
  expected="$(env_value ASTRAVECTOR_EXPECTED_DIGEST)"
  digests="$(docker image inspect "$image" --format '{{join .RepoDigests "\n"}}' 2>/dev/null || true)"
  if [ -n "$digests" ] && ! printf '%s\n' "$digests" | grep -Fq "$expected"; then
    echo "ERROR: local AstraVector image digest does not include expected digest ${expected}" >&2
    exit 1
  fi
else
  echo "INFO: AstraVector image is not present locally; start.sh will pull it from the private registry."
fi

echo "PREFLIGHT_PASS"
