# AstraDeployment Portable Local 1.0 Validation Result

## Verdict

ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_VALIDATION_PASS

## Tested Revision

```text
base: 509344b8ce25b8df37655ab4a35ba1d6ac5a270a
validated with local fixes in this branch/worktree
```

## Host And Docker

```text
uname -m: arm64
docker architecture: aarch64
root filesystem available before runtime: 12 GiB
docker system df:
  Images:        12 total, 17.86GB
  Containers:    25 total, 6.906MB
  Local Volumes: 27 total, 9.42GB
  Build Cache:   43 total, 13.49GB
```

## Fixes Applied During Validation

Validation initially exposed three deployment defects. They were fixed and re-tested:

1. `make start` failed in a fresh clone because `start.sh` executed sibling scripts directly while scripts were committed as `100644`. Fixed by invoking sibling scripts through `bash`.
2. A preloaded model cache volume was not writable by the non-root AstraVector image user `10001:10001`. Fixed by adding a `model-cache-init` service that prepares model-cache ownership before AstraVector starts.
3. `helper_grpcurl` used `docker run` without `-i`, so `grpcurl -d @` received empty stdin. Fixed by adding `-i`.
4. The smoke gRPC JSON payload was aligned to proto field names and a deterministic UUID access zone. The final REST retrieve uses `SEMANTIC` profile for the dense-only smoke document.

No real secrets were committed.

## Static Audit

| Gate | Result | Evidence |
| --- | --- | --- |
| Architecture spec read | PASS | `docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_SPEC.md` defines PostgreSQL canonical state, Qdrant rebuildable projection, model cache, Compose lifecycle, health and smoke contracts. |
| `deploy/local/` inspected | PASS | Compose, Makefile, scripts, `.env.example`, README and recovery docs inspected. |
| `.env` gitignored | PASS | `git check-ignore -v deploy/local/.env` returned `.gitignore:1:deploy/local/.env`. |
| Secret scan | PASS | Search for known credentials, auth headers and bearer tokens returned no committed matches. |
| Shell syntax | PASS | `bash -n deploy/local/scripts/*.sh` passed after fixes. |
| Compose render | PASS | `docker compose --env-file .env -f docker-compose.astravector.yml config` rendered successfully. |
| PostgreSQL public exposure | PASS | Compose does not publish PostgreSQL ports. |
| Published ports loopback-only | PASS | AstraVector gRPC/HTTP/metrics and Qdrant diagnostics render with `host_ip: 127.0.0.1`. |
| Cleanup preserves volumes | PASS | `make cleanup` removed containers/network and preserved named volumes. |
| Destructive cleanup guard | PASS | `cleanup.sh --delete-data` requires explicit typed `DELETE`. Not executed. |

## Image Identity

```text
image: registry.astrabase.asia/astravector:sha-1cb6065
architecture: arm64
os: linux
RepoDigest: registry.astrabase.asia/astravector@sha256:b0567810b5ea3df752ff8ba559fcf16bc46b245878e798b8888dcf93426ee6ad
```

## Model Cache

The run used the documented warm-cache/recovery path. The `astradeployment-model-cache` volume was prepared from local verified model artifacts.

Checksums inside Docker volume:

```text
f84251230831afb359ab26d9fd37d5936d4d9bb5d1d5410e66442f630f24435b  /models/model.onnx
1eebfb28493f67bba03ce0ef64bfdc7fc5a3bd9d7493f818bb1d78cd798416b4  /models/model.onnx_data
21106b6d7dab2952c1d496fb21d5dc9db75c28ed361a05f5020bbba27810dd08  /models/tokenizer.json
```

Runtime logs confirmed warm-cache behavior:

```text
[astravector-bootstrap] cache valid: model.onnx
[astravector-bootstrap] cache valid: model.onnx_data
[astravector-bootstrap] cache valid: tokenizer.json
[astravector-bootstrap] PostgreSQL reachable at postgres:5432
[astravector-bootstrap] Qdrant reachable at qdrant:6333
[astravector-bootstrap] model and dependency bootstrap complete
```

Cold Nexus download was not re-tested in this run. The known external large-transfer limitation remains recorded separately.

## Operator Path

### `make preflight`

PASS.

```text
Docker: ready
Architecture: arm64
Free disk: 11 GiB
Model cache: existing
PREFLIGHT_PASS
```

### `make start`

PASS.

```text
ASTRADEPLOYMENT_HEALTH_PASS
ASTRADEPLOYMENT_START_PASS
```

Health gates passed:

- PostgreSQL healthy.
- Qdrant reachable.
- AstraVector `/ready` ready.
- gRPC health for `astravector.embedding.v1.AstraVectorRuntime` returned `SERVING`.

## Functional Smoke

`make smoke` PASS.

The smoke executed real:

```text
IndexLogicalDocument
GetDocumentVectorStatus
ActivateDocumentVersion
POST /api/v1/retrieve
```

Observed evidence:

```text
AstraVector хранит каноническое состояние документов в PostgreSQL.
```

The REST retrieval summary included:

```text
profile: SEMANTIC
evidenceStatus: FOUND
returnedContexts: 1
denseBranchExecuted: true
sparseBranchExecuted: false
```

## Persistence And Restart

PASS.

Sequence executed:

```text
make stop
make start
make smoke
```

The second `make start` reused the existing model cache and returned `ASTRADEPLOYMENT_START_PASS`. The second `make smoke` returned `ASTRADEPLOYMENT_SMOKE_PASS` and retrieved the same PostgreSQL evidence.

Named volumes preserved:

```text
astradeployment-model-cache
astradeployment-postgres-data
astradeployment-qdrant-data
```

## Stop Behavior

Recorded AstraVector exit behavior after `make stop`:

```text
/astradeployment-astravector-1 ExitCode=137 OOMKilled=false Status=exited
/astradeployment-postgres-1 ExitCode=0 OOMKilled=false Status=exited
/astradeployment-qdrant-1 ExitCode=143 OOMKilled=false Status=exited
```

This confirms the historical AstraVector graceful-shutdown defect is still present in the current `sha-1cb6065` image. The deployment bundle uses a conservative 90s grace period, but the application image still exits via forced stop. This is not hidden and is not claimed fixed here.

## Cleanup

PASS.

`make cleanup` removed Compose containers and network while preserving persistent volumes:

```text
astradeployment-model-cache
astradeployment-postgres-data
astradeployment-qdrant-data
```

## Remaining Known Defects / Limitations

1. AstraVector image `sha-1cb6065` still does not exit gracefully under Compose stop; observed `ExitCode=137`, `OOMKilled=false`.
2. Fresh cold transfer of `model.onnx_data` from Nexus remains an external large-file delivery limitation; this validation used the official warm-cache/recovery path.

## Final Result

ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_VALIDATION_PASS
