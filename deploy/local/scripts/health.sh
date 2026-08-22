#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

wait_mode=false
timeout=300
if [ "${1:-}" = "--wait" ]; then
  wait_mode=true
  timeout="${2:-300}"
fi

deadline=$(( $(date +%s) + timeout ))

check_once() {
  compose ps

  compose exec -T postgres pg_isready \
    -U "$(env_value POSTGRES_USER)" \
    -d "$(env_value POSTGRES_DB)" >/dev/null || return 1

  helper_curl -fsS http://qdrant:6333/collections >/dev/null || return 1
  helper_curl -fsS http://astravector:8080/ready | grep -q '"ready":true' || return 1

  grpc_out="$(helper_grpcurl -plaintext \
    -d '{"service":"astravector.embedding.v1.AstraVectorRuntime"}' \
    astravector:50051 grpc.health.v1.Health/Check 2>/dev/null)" || return 1
  printf '%s' "$grpc_out" | grep -q 'SERVING' || return 1

  return 0
}

if [ "$wait_mode" = true ]; then
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if check_once; then
      echo "ASTRADEPLOYMENT_HEALTH_PASS"
      exit 0
    fi
    echo "waiting for AstraDeployment health..." >&2
    sleep 5
  done
  echo "ERROR: health timeout after ${timeout}s" >&2
  compose logs --tail 100 astravector >&2 || true
  exit 1
fi

check_once
echo "ASTRADEPLOYMENT_HEALTH_PASS"
