#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

bash "${SCRIPT_DIR}/preflight.sh"

image="$(env_value ASTRAVECTOR_IMAGE)"
expected="$(env_value ASTRAVECTOR_EXPECTED_DIGEST)"

echo "Pulling declared images..."
compose pull

digests="$(docker image inspect "$image" --format '{{join .RepoDigests "\n"}}' 2>/dev/null || true)"
if [ -z "$digests" ] || ! printf '%s\n' "$digests" | grep -Fq "$expected"; then
  echo "ERROR: pulled AstraVector image does not expose expected digest ${expected}" >&2
  docker image inspect "$image" --format 'ARCH={{.Architecture}} OS={{.Os}} DIGESTS={{json .RepoDigests}}' >&2 || true
  exit 1
fi

docker image inspect "$image" --format 'AstraVector image: ARCH={{.Architecture}} OS={{.Os}} DIGESTS={{json .RepoDigests}}'

echo "Starting AstraDeployment..."
compose up -d

bash "${SCRIPT_DIR}/health.sh" --wait "${ASTRADEPLOYMENT_START_TIMEOUT_SECONDS:-600}"

echo "ASTRADEPLOYMENT_START_PASS"
