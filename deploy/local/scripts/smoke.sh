#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

bash "${SCRIPT_DIR}/health.sh"

SMOKE_DIR="${LOCAL_DIR}/.smoke"
mkdir -p "$SMOKE_DIR"

text='AstraVector хранит каноническое состояние документов в PostgreSQL. Qdrant используется как перестраиваемая поисковая проекция. Модель BGE-M3 загружается из Nexus и используется для построения эмбеддингов.'
question='Где AstraVector хранит каноническое состояние документов?'
expected='AstraVector хранит каноническое состояние документов в PostgreSQL.'
document_id='4b1f929e-6cd9-4c85-8d43-efe2485c9e10'
access_zone_id='b4ec78f9-70c3-5264-8b75-1b85f1905e44'
root_block_id='c0409001-bb0e-4e70-b0c4-06b3b5f69301'
paragraph_block_id='c0409001-bb0e-4e70-b0c4-06b3b5f69302'

sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  fi
}

content_hash="$(sha256_text "$text")"
correlation="astradeployment-smoke-$(date +%s)"

cat >"${SMOKE_DIR}/ingest.json" <<EOF
{
  "context": {
    "correlation_id": "${correlation}",
    "idempotency_key": "astradeployment:${document_id}:1:${content_hash}",
    "caller_service": "astradeployment-smoke",
    "caller_user_id": "local-operator",
    "caller_access_level": "PUBLIC"
  },
  "access_zone_id": "${access_zone_id}",
  "access_zone_code": "0488",
  "document": {
    "external_document_id": "astradeployment-portable-local-smoke",
    "document_id": "${document_id}",
    "document_version": 1,
    "title": "AstraDeployment Portable Local Smoke",
    "source_uri": "astradeployment://smoke/ru",
    "source_type": "PLAIN_TEXT",
    "mime_type": "text/plain; charset=utf-8",
    "content_hash": "${content_hash}"
  },
  "blocks": [
    {
      "block_id": "${root_block_id}",
      "block_type": "BLOCK_TYPE_DOCUMENT",
      "text": "AstraDeployment smoke document root.",
      "order_index": 0
    },
    {
      "block_id": "${paragraph_block_id}",
      "parent_block_id": "${root_block_id}",
      "block_type": "BLOCK_TYPE_PARAGRAPH",
      "text": "${text}",
      "order_index": 1
    }
  ],
  "chunking_options": {
    "profile": "CHUNKING_PROFILE_DEFAULT",
    "preserve_block_boundaries": true,
    "create_parent_context": true
  },
  "indexing_options": {
    "activation_policy": "ACTIVATION_POLICY_MANUAL",
    "embedding_mode": "EMBEDDING_MODE_V005_DENSE_ONLY",
    "publish_mode": "PUBLISH_MODE_V005_OUTBOX",
    "ttl_policy": {"mode": "TTL_MODE_NONE"},
    "replace_existing_version": true
  },
  "metadata": {
    "deployment": "astradeployment-portable-local-1.0",
    "smoke": "true"
  }
}
EOF

ingest="$(helper_grpcurl -plaintext -d @ astravector:50051 \
  astravector.embedding.v1.AstraVectorIngestionFacade/IndexLogicalDocument \
  <"${SMOKE_DIR}/ingest.json")"
printf '%s\n' "$ingest" >"${SMOKE_DIR}/ingestion-response.json"
printf '%s\n' "$ingest"

resolved_access_zone_id="$(printf '%s\n' "$ingest" | sed -n 's/.*"accessZoneId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
if [ -z "$resolved_access_zone_id" ]; then
  echo "ERROR: ingestion response did not contain document.accessZoneId" >&2
  exit 1
fi
access_zone_id="$resolved_access_zone_id"

ready=false
for _ in $(seq 1 120); do
  status_payload="{\"context\":{\"correlation_id\":\"astradeployment-status\",\"caller_service\":\"astradeployment-smoke\",\"caller_access_level\":\"PUBLIC\"},\"document\":{\"access_zone_id\":\"${access_zone_id}\",\"document_id\":\"${document_id}\",\"document_version\":1},\"include_qdrant\":true}"
  status="$(helper_grpcurl -plaintext -d "$status_payload" astravector:50051 \
    astravector.embedding.v1.AstraVectorIngestionFacade/GetDocumentVectorStatus)"
  printf '%s\n' "$status" >"${SMOKE_DIR}/vector-status.json"
  if printf '%s' "$status" | grep -Eq '"readyToActivate"[[:space:]]*:[[:space:]]*true|OPERATION_STATE_READY_TO_ACTIVATE'; then
    ready=true
    break
  fi
  if printf '%s' "$status" | grep -Eq 'OPERATION_STATE_FAILED|"outboxFailed"[[:space:]]*:[[:space:]]*[1-9]'; then
    echo "ERROR: vector publication failed" >&2
    printf '%s\n' "$status" >&2
    exit 1
  fi
  sleep 1
done

if [ "$ready" != true ]; then
  echo "ERROR: document did not become ready to activate" >&2
  cat "${SMOKE_DIR}/vector-status.json" >&2
  exit 1
fi

activation_payload="{\"access_zone_id\":\"${access_zone_id}\",\"document_id\":\"${document_id}\",\"document_version\":1}"
activation="$(helper_grpcurl -plaintext -d "$activation_payload" astravector:50051 \
  astravector.embedding.v1.AstraVectorV004Control/ActivateDocumentVersion)"
printf '%s\n' "$activation" >"${SMOKE_DIR}/activation-response.json"
printf '%s\n' "$activation"

retrieve_payload="{\"question\":\"${question}\",\"accessZoneId\":\"${access_zone_id}\",\"accessZoneCode\":\"0488\",\"callerAccessLevel\":\"PUBLIC\",\"profile\":\"SEMANTIC\",\"maxContexts\":3,\"responseDetail\":\"STANDARD\",\"enableGraphExpansion\":false,\"correlationId\":\"astradeployment-retrieve\"}"
retrieval="$(helper_curl -fsS -H 'content-type: application/json' -d "$retrieve_payload" http://astravector:8080/api/v1/retrieve)"
printf '%s\n' "$retrieval" >"${SMOKE_DIR}/retrieval-response.json"
printf '%s\n' "$retrieval"

if ! printf '%s' "$retrieval" | grep -Fq "$expected"; then
  echo "ERROR: retrieval did not contain expected PostgreSQL evidence" >&2
  exit 1
fi

echo "ASTRADEPLOYMENT_SMOKE_PASS"
