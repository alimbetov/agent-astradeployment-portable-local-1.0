# Codex Validation Task — AstraDeployment Portable Local Deployment 1.0

## Role

Act only as an independent validation engineer.

Do NOT redesign or implement AstraDeployment in this task. The architecture and implementation are already present in this repository.

Primary source of truth:

```text
docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_SPEC.md
```

Operator bundle:

```text
deploy/local/
```

## Goal

Prove whether a fresh clone can reproduce the declared single-node AstraVector environment and execute the functional smoke.

You may create only validation evidence/result files. Do not modify Compose, scripts, architecture, AstraVector code or application semantics unless explicitly asked after a failed audit.

## Baseline identities

AstraVector:

```text
registry.astrabase.asia/astravector:sha-f6493fa
sha256:2957a8887443e53914ca07816ddbaab385e02b96a81b7a08b4a1697f94f0ac40
```

PostgreSQL:

```text
pgvector/pgvector:pg16
```

Qdrant:

```text
qdrant/qdrant:v1.14.1
```

The currently proven AstraVector image is arm64. Do not claim amd64 portability without an actual matching image.

## Required validation sequence

### 1. Static audit

From a fresh clone:

- read the architecture spec;
- inspect all files under `deploy/local/`;
- verify `.env` is gitignored;
- verify no real secrets are committed;
- run shell syntax checks on all `.sh` files;
- run `docker compose config` using a temporary local `.env` with non-production test secrets;
- verify default cleanup preserves volumes;
- verify destructive cleanup requires explicit confirmation;
- verify published ports are loopback-only;
- verify PostgreSQL is not exposed publicly;
- verify smoke uses real AstraVector service names and REST path from the source contract.

### 2. Disk/architecture preflight

Record:

```text
uname -m
docker info --format '{{.Architecture}}'
df -h /
docker system df
```

Do not automatically run `docker volume prune`.

### 3. Registry authentication

Authenticate interactively with the reader/puller account. Do not print or commit the password.

Then pull the declared AstraVector image and record:

- RepoDigest;
- architecture;
- OS.

The expected digest is the baseline recorded above.

### 4. Configure `.env`

Create `deploy/local/.env` locally only.

Use disposable local PostgreSQL credentials and the supplied Nexus reader credentials.

`ASTRAVECTOR_DB_URL` must refer to Compose DNS name `postgres`, not localhost.

Never commit `.env`.

### 5. Start

Execute the operator path exactly as documented:

```bash
cd deploy/local
make preflight
make start
```

Record whether:

- PostgreSQL becomes healthy;
- Qdrant responds;
- AstraVector `/ready` becomes READY;
- gRPC health for `astravector.embedding.v1.AstraVectorRuntime` returns SERVING.

### 6. Model path

If model cache is already valid, record warm-cache behavior.

If model cache is empty, attempt the cold Nexus download but do not reinterpret the known large-transfer limitation as an AstraDeployment architecture defect unless the bundle itself causes the failure.

After a valid model is available, verify exact SHA-256 values for:

```text
model.onnx
model.onnx_data
tokenizer.json
```

### 7. Functional smoke

Run exactly:

```bash
make smoke
```

PASS requires real ingestion/vector publication/activation/retrieval and evidence containing:

```text
AstraVector хранит каноническое состояние документов в PostgreSQL.
```

Do not replace the smoke with a simulated request.

### 8. Persistence/restart

Record named volumes before restart.

Run:

```bash
make stop
make start
make smoke
```

Confirm:

- PostgreSQL state persists;
- Qdrant state persists or remains reconstructible/valid;
- model cache is reused and not unnecessarily re-downloaded;
- smoke remains successful.

### 9. Stop behavior

Record actual AstraVector container exit behavior after normal `make stop`.

The historical baseline has a known graceful-shutdown defect (`ExitCode=137` after a 45-second stop). Do not claim it is fixed unless the actual run proves it.

### 10. Safe cleanup

Run non-destructive cleanup:

```bash
make cleanup
```

Verify named volumes remain.

Do not run `make destroy` unless an isolated disposable validation environment was explicitly authorized.

## Required evidence file

Create:

```text
docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_VALIDATION_RESULT.md
```

Record:

- tested Git SHA;
- host/Docker architecture;
- image digest;
- Compose validation result;
- secret scan result;
- preflight result;
- health results;
- model cache/cold-download result;
- exact model checksums if available;
- smoke result;
- persistence/restart result;
- stop/ExitCode result;
- cleanup result;
- all blockers separately from implementation defects.

## Verdict

Use exactly one:

```text
ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_VALIDATION_PASS
ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_VALIDATION_FAIL
ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_VALIDATION_BLOCKED
```

PASS requires:

- static contract PASS;
- actual Compose startup PASS;
- health PASS;
- functional smoke PASS;
- restart persistence PASS;
- safe cleanup PASS.

A known external cold-transfer limitation may be recorded as a limitation when a valid preloaded/warm model cache is used; it must not be hidden.

Do not make implementation changes in order to manufacture PASS. Report defects for the architect to fix in a separate iteration.
