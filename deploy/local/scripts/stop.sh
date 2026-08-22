#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

compose stop

echo "AstraDeployment containers stopped. Persistent volumes were preserved."
echo "Known baseline note: AstraVector graceful shutdown previously required force-kill after 45s; current Compose grace period is intentionally conservative and must be validated."
