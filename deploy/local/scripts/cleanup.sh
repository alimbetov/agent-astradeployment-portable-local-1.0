#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

if [ "${1:-}" = "--delete-data" ]; then
  echo "WARNING: this will permanently delete PostgreSQL canonical state, Qdrant data and the model cache." >&2
  printf 'Type DELETE to continue: ' >&2
  read -r answer
  [ "$answer" = "DELETE" ] || {
    echo "Cancelled." >&2
    exit 1
  }
  compose down -v --remove-orphans
  echo "AstraDeployment containers, network and persistent volumes deleted."
else
  compose down --remove-orphans
  echo "AstraDeployment containers/network removed. Persistent volumes preserved."
fi
