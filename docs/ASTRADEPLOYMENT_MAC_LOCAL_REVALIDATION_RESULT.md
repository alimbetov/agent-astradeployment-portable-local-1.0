# AstraDeployment Mac Local Revalidation Result

## Verdict

ASTRADEPLOYMENT_MAC_LOCAL_REVALIDATION_PASS

## Tested Source

```text
repository: https://github.com/alimbetov/agent-astradeployment-portable-local-1.0
fresh checkout path: /Users/ruslanalimbetov/Documents/llm2/agent-astradeployment-portable-local-1.0-revalidation
base commit: bd89278f6fe4e75bf816196c2ccc092cd600bdc1
```

One minimal deployment-bundle fix was applied during this revalidation:

```text
ASTRAVECTOR_SINGLE_QUERY_DEADLINE_MS=3000
```

Reason: the repeated Mac smoke initially reproduced an HTTP retrieve `504` because AstraVector's single-query planner still used its image default of `1000 ms`. After exposing and setting the single-query deadline alongside `ASTRAVECTOR_GRPC_QUERY_DEADLINE_MS=3000`, `make smoke` returned `ASTRADEPLOYMENT_SMOKE_PASS` and diagnostics reported `effectiveQueryTimeoutMs: 3000`.

## Host And Docker

```text
uname -m: arm64
Docker client: 28.3.3, darwin/arm64
Docker server: Docker Desktop 4.43.2, Engine 28.3.2, linux/arm64
Docker Compose: v2.38.2-desktop.1
docker system df:
  Images:        15 total, 18.56GB
  Containers:    25 total, 6.906MB
  Local Volumes: 30 total, 12.91GB
  Build Cache:   43 total, 13.49GB
```

## Static Validation

| Check | Result | Evidence |
| --- | --- | --- |
| Fresh checkout | PASS | Fresh clone at the path above. |
| Shell syntax | PASS | `bash -n deploy/local/scripts/*.sh` passed. |
| `.env` ignored | PASS | `git check-ignore -v deploy/local/.env` returned `.gitignore:1:deploy/local/.env`. |
| Secret scan | PASS | Search for known credentials, auth headers and bearer tokens returned no committed matches. |
| Compose render | PASS | `docker compose --env-file .env -f docker-compose.astravector.yml config` rendered successfully. |
| PostgreSQL exposure | PASS | PostgreSQL has no public host port. |
| Loopback ports | PASS | AstraVector gRPC/HTTP/metrics and Qdrant diagnostics render with `host_ip: 127.0.0.1`. |
| Persistent volumes | PASS | Compose defines `astradeployment-postgres-data`, `astradeployment-qdrant-data`, `astradeployment-model-cache`. |
| Destructive cleanup guard | PASS | `cleanup.sh --delete-data` requires explicit typed `DELETE`. Not executed. |

## Image Identity

```text
docker pull registry.astrabase.asia/astravector:sha-1cb6065
Digest: sha256:b0567810b5ea3df752ff8ba559fcf16bc46b245878e798b8888dcf93426ee6ad
Status: Image is up to date
```

Image inspect:

```text
ARCH=arm64
OS=linux
RepoDigest=registry.astrabase.asia/astravector@sha256:b0567810b5ea3df752ff8ba559fcf16bc46b245878e798b8888dcf93426ee6ad
```

## Model Cache

Warm/preloaded cache path was used. SHA-256 values inside `astradeployment-model-cache`:

```text
f84251230831afb359ab26d9fd37d5936d4d9bb5d1d5410e66442f630f24435b  /models/model.onnx
1eebfb28493f67bba03ce0ef64bfdc7fc5a3bd9d7493f818bb1d78cd798416b4  /models/model.onnx_data
21106b6d7dab2952c1d496fb21d5dc9db75c28ed361a05f5020bbba27810dd08  /models/tokenizer.json
```

Startup logs confirmed warm-cache reuse:

```text
[astravector-bootstrap] cache valid: model.onnx
[astravector-bootstrap] cache valid: model.onnx_data
[astravector-bootstrap] cache valid: tokenizer.json
[astravector-bootstrap] PostgreSQL reachable at postgres:5432
[astravector-bootstrap] Qdrant reachable at qdrant:6333
[astravector-bootstrap] model and dependency bootstrap complete
```

Cold Nexus download was not used as the release gate in this revalidation.

## Commands Executed

```text
make preflight
make start
make health
make smoke
make stop
make start
make health
make smoke
make cleanup
```

Operator outputs included:

```text
PREFLIGHT_PASS
ASTRADEPLOYMENT_START_PASS
ASTRADEPLOYMENT_HEALTH_PASS
ASTRADEPLOYMENT_SMOKE_PASS
```

## Smoke Evidence

The smoke executed the real integration chain:

```text
IndexLogicalDocument
GetDocumentVectorStatus
ActivateDocumentVersion
POST /api/v1/retrieve
```

Observed ingestion:

```text
state: OPERATION_STATE_INDEXING
blocksReceived: 2
blocksAccepted: 2
chunksCreated: 7
parentChunksCreated: 2
childChunksCreated: 4
```

Observed activation:

```text
documentId: 4b1f929e-6cd9-4c85-8d43-efe2485c9e10
documentVersion: 1
status: ACTIVE
```

Observed retrieval:

```text
summary.evidenceStatus: FOUND
summary.profile: SEMANTIC
summary.returnedContexts: 1
summary.denseBranchExecuted: true
summary.sparseBranchExecuted: false
diagnostics.effectiveQueryTimeoutMs: 3000
```

Expected evidence returned:

```text
AstraVector хранит каноническое состояние документов в PostgreSQL.
```

Generated local evidence files were inspected under:

```text
deploy/local/.smoke/
  ingest.json
  ingestion-response.json
  vector-status.json
  activation-response.json
  retrieval-response.json
```

## Restart And Persistence

Restart sequence passed:

```text
make stop
make start
make health
make smoke
```

After restart:

- PostgreSQL volume persisted.
- Qdrant volume persisted.
- model cache volume persisted and was reused.
- second smoke returned `ASTRADEPLOYMENT_SMOKE_PASS`.
- second retrieval returned the same expected Russian evidence.

Stop exit codes recorded after `make stop`:

```text
/astradeployment-astravector-1 ExitCode=137 OOMKilled=false Status=exited
/astradeployment-postgres-1 ExitCode=0 OOMKilled=false Status=exited
/astradeployment-qdrant-1 ExitCode=143 OOMKilled=false Status=exited
```

The known AstraVector graceful-shutdown lifecycle defect remains present and documented. It did not invalidate deployment G1-G15 because restart, persistence and repeated smoke passed.

## Cleanup

`make cleanup` removed containers and network. No `astradeployment-*` containers remained afterwards.

Named volumes were preserved:

```text
astradeployment-model-cache
astradeployment-postgres-data
astradeployment-qdrant-data
```

## Acceptance Gates

| Gate | Result |
| --- | --- |
| G1 fresh checkout works | PASS |
| G2 compose renders | PASS |
| G3 exact AstraVector image/digest validated | PASS |
| G4 preflight PASS | PASS |
| G5 start PASS | PASS |
| G6 HTTP readiness PASS | PASS |
| G7 gRPC SERVING PASS | PASS |
| G8 ingestion PASS | PASS |
| G9 vector publication PASS | PASS |
| G10 activation PASS | PASS |
| G11 HTTP retrieval PASS | PASS |
| G12 expected Russian evidence returned | PASS |
| G13 restart PASS | PASS |
| G14 repeated smoke PASS | PASS |
| G15 cleanup preserves persistent volumes | PASS |

## Known Defects / Limitations

1. AstraVector image `sha-1cb6065` still exits with `ExitCode=137`, `OOMKilled=false` after Compose stop.
2. Cold Nexus transfer of `model.onnx_data` remains a known external large-file delivery limitation and was not used as the primary release gate.

## Final Result

ASTRADEPLOYMENT_MAC_LOCAL_REVALIDATION_PASS
