# AstraVector Image Refresh Result 2026-08-29

## Verdict

```text
ASTRAVECTOR_IMAGE_REFRESH_PASS
```

## Source

```text
Repository: alimbetov/llm2
Branch: main
Commit: f6493fa86d8c7c80678989ffcb8858b5f5b684dd
```

The source includes the session-finalize activation remediation merged into `main` and the follow-up formatting fix required for green CI.

## Published image

```text
registry.astrabase.asia/astravector:sha-f6493fa
registry.astrabase.asia/astravector:0.4.1-image-contract
```

Remote OCI index digest:

```text
sha256:2957a8887443e53914ca07816ddbaab385e02b96a81b7a08b4a1697f94f0ac40
```

Remote inspect confirmed both tags point to the same digest and contain a `linux/arm64` manifest.

## Local static image check

```text
Image ID: sha256:2957a8887443e53914ca07816ddbaab385e02b96a81b7a08b4a1697f94f0ac40
OS/architecture: linux/arm64
Runtime user: 10001:10001
Large BGE-M3 model bundle: not embedded in image
```

The image contains:

```text
/usr/local/bin/astravector-runtime
/usr/local/bin/astravector-model-bootstrap
/usr/local/bin/astravector-entrypoint
```

## Deployment update

The portable local deployment now defaults to:

```text
ASTRAVECTOR_IMAGE=registry.astrabase.asia/astravector:sha-f6493fa
ASTRAVECTOR_EXPECTED_DIGEST=sha256:2957a8887443e53914ca07816ddbaab385e02b96a81b7a08b4a1697f94f0ac40
```

## Mac local validation

Host:

```text
Architecture: arm64
Model cache: existing
Free disk after safe image cleanup: 8 GiB
```

Commands:

```text
make preflight -> PREFLIGHT_PASS
make start     -> ASTRADEPLOYMENT_START_PASS
make health    -> ASTRADEPLOYMENT_HEALTH_PASS
make smoke     -> ASTRADEPLOYMENT_SMOKE_PASS
make stop      -> containers stopped, persistent volumes preserved
```

The first start attempt exposed a reused PostgreSQL volume credential mismatch:

```text
password authentication failed for user "astravector_app"
```

Resolution: the PostgreSQL role password was synchronized inside the existing `astradeployment-postgres-data` volume with the current Compose environment. No PostgreSQL, Qdrant or model-cache volume was deleted.

The known AstraVector graceful-shutdown limitation reproduced after the successful smoke:

```text
astradeployment-astravector-1 Exited (137)
astradeployment-postgres-1    Exited (0)
astradeployment-qdrant-1      Exited (143)
```

This did not affect readiness, ingestion, activation or retrieval evidence for this refresh.

## Smoke input

Question:

```text
Где AstraVector хранит каноническое состояние документов?
```

Indexed logical blocks included:

```text
AstraDeployment smoke document root.
```

```text
AstraVector хранит каноническое состояние документов в PostgreSQL. Qdrant используется как перестраиваемая поисковая проекция. Модель BGE-M3 загружается из Nexus и используется для построения эмбеддингов.
```

## Smoke output

Ingestion:

```text
state: OPERATION_STATE_INDEXING
blocksReceived: 2
blocksAccepted: 2
chunksCreated: 7
parentChunksCreated: 2
childChunksCreated: 4
```

Activation:

```text
status: ACTIVE
```

Retrieval evidence:

```text
AstraVector хранит каноническое состояние документов в PostgreSQL. Qdrant используется как перестраиваемая поисковая проекция. Модель BGE-M3 загружается из Nexus и используется для построения эмбеддингов.
```

Retrieval summary:

```text
evidenceStatus: FOUND
degraded: false
returnedContexts: 1
profile: SEMANTIC
effectiveQueryTimeoutMs: 3000
```

## AstraIndexator contract note

AstraIndexator must pass parsed logical document content to AstraVector through the public gRPC ingestion facade. It must not write directly into AstraVector PostgreSQL or Qdrant.

Minimum validated lifecycle:

```text
IndexLogicalDocument
-> GetDocumentVectorStatus
-> ActivateDocumentVersion
-> POST /api/v1/retrieve
```
