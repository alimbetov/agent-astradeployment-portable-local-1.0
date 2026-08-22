# Codex Task — AstraDeployment Mac Local Revalidation

## Goal

Re-run AstraDeployment Portable Local Deployment 1.0 from a fresh local checkout on Apple Silicon/macOS and prove the deployment still works end-to-end before AstraIndexator development begins.

Repository:

`https://github.com/alimbetov/agent-astradeployment-portable-local-1.0`

This is a validation task. Do not redesign the architecture and do not change AstraVector internals. Only make minimal deployment-bundle fixes if a validation defect is encountered, and document every such fix.

## Preconditions

Host must be macOS on Apple Silicon / arm64 with Docker Desktop or compatible Docker Engine and Docker Compose v2.

The tested AstraVector image baseline is:

```text
registry.astrabase.asia/astravector:sha-1cb6065
expected digest: sha256:b0567810b5ea3df752ff8ba559fcf16bc46b245878e798b8888dcf93426ee6ad
```

Use the current repository `main` revision as the deployment source of truth.

Do not expose or commit real secrets.

## Required validation sequence

### 1. Fresh clone

Use a fresh directory/worktree.

Record:

```bash
git rev-parse HEAD
uname -m
docker version
docker compose version
docker system df
```

Expected host architecture: `arm64` / `aarch64`.

### 2. Static validation

Inspect:

```text
deploy/local/docker-compose.astravector.yml
deploy/local/.env.example
deploy/local/Makefile
deploy/local/scripts/*.sh
deploy/local/recovery/README.md
docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_SPEC.md
```

Run at minimum:

```bash
bash -n deploy/local/scripts/*.sh
```

Create local `.env` from `.env.example` and run:

```bash
docker compose --env-file .env -f docker-compose.astravector.yml config
```

Verify:

- PostgreSQL has no public host port;
- AstraVector/Qdrant published diagnostics are loopback-only;
- persistent volumes exist for PostgreSQL, Qdrant and model cache;
- no real credentials exist in committed files;
- destructive cleanup still requires explicit confirmation.

### 3. Registry and image identity

Authenticate interactively with the private registry. Do not write the password into scripts or logs.

```bash
docker login registry.astrabase.asia -u astra-reader
```

Pull the exact configured AstraVector image.

Verify architecture and repo digest. The observed repo digest must equal the expected digest above.

If it does not match, stop and mark validation FAIL/BLOCKED. Do not silently update the expected digest.

### 4. Model cache path

Preferred path for this validation is the already-supported warm/preloaded cache path.

Verify SHA-256 inside the model cache for:

```text
model.onnx
f84251230831afb359ab26d9fd37d5936d4d9bb5d1d5410e66442f630f24435b

model.onnx_data
1eebfb28493f67bba03ce0ef64bfdc7fc5a3bd9d7493f818bb1d78cd798416b4

tokenizer.json
21106b6d7dab2952c1d496fb21d5dc9db75c28ed361a05f5020bbba27810dd08
```

Cold download from Nexus is NOT a release gate for this revalidation because the existing large-file transfer limitation is already documented. If tested, record it separately without changing the primary verdict unless the deployment itself depends on it.

### 5. Operator path

From `deploy/local` run exactly:

```bash
make preflight
make start
make health
make smoke
```

Expected:

```text
PREFLIGHT_PASS
ASTRADEPLOYMENT_START_PASS
ASTRADEPLOYMENT_HEALTH_PASS
ASTRADEPLOYMENT_SMOKE_PASS
```

The health gate must prove:

- PostgreSQL healthy;
- Qdrant reachable;
- AstraVector HTTP `/ready` passes;
- gRPC health service `astravector.embedding.v1.AstraVectorRuntime` returns `SERVING`.

### 6. Functional smoke semantics

The smoke must execute the real integration chain:

```text
IndexLogicalDocument
→ GetDocumentVectorStatus
→ ActivateDocumentVersion
→ POST /api/v1/retrieve
```

Expected semantic evidence:

```text
AstraVector хранит каноническое состояние документов в PostgreSQL.
```

The retrieval result must show semantic evidence found and dense retrieval execution for the current smoke profile.

Store/inspect generated `.smoke/` evidence and record relevant files in the result document.

### 7. Restart and persistence

Run:

```bash
make stop
make start
make health
make smoke
```

Verify:

- PostgreSQL data survived;
- Qdrant/model volumes survived;
- model cache is reused and checksum-valid;
- second smoke returns the same expected evidence.

Record AstraVector exit code after `make stop`.

Known historical defect:

```text
ExitCode=137
OOMKilled=false
```

If still reproduced, record it as an AstraVector image lifecycle defect. Do not mark the deployment invalid solely for this known issue if restart/persistence/smoke all pass.

### 8. Cleanup semantics

Run:

```bash
make cleanup
```

Verify containers/network are removed but these named volumes remain:

```text
astradeployment-postgres-data
astradeployment-qdrant-data
astradeployment-model-cache
```

Do NOT run destructive `make destroy` unless needed for an isolated test. If destructive cleanup is inspected, verify the explicit `DELETE` confirmation guard.

## Smoke acceptance gates

All must pass:

```text
G1 fresh checkout works
G2 compose renders
G3 exact AstraVector image/digest validated
G4 preflight PASS
G5 start PASS
G6 HTTP readiness PASS
G7 gRPC SERVING PASS
G8 ingestion PASS
G9 vector publication PASS
G10 activation PASS
G11 HTTP retrieval PASS
G12 expected Russian evidence returned
G13 restart PASS
G14 repeated smoke PASS
G15 cleanup preserves persistent volumes
```

Known AstraVector graceful shutdown defect may remain as a documented limitation and does not invalidate G1-G15 by itself.

## Result document

Create/update:

```text
docs/ASTRADEPLOYMENT_MAC_LOCAL_REVALIDATION_RESULT.md
```

Include:

- tested commit SHA;
- host architecture and Docker versions;
- exact image identity and digest;
- model cache checksums;
- commands executed;
- PASS/FAIL for each G1-G15;
- smoke evidence;
- restart/persistence evidence;
- cleanup evidence;
- known defects;
- any bundle fixes made during validation.

Final verdict must be exactly one of:

```text
ASTRADEPLOYMENT_MAC_LOCAL_REVALIDATION_PASS
ASTRADEPLOYMENT_MAC_LOCAL_REVALIDATION_FAIL
ASTRADEPLOYMENT_MAC_LOCAL_REVALIDATION_BLOCKED
```

## Scope restriction

Do not begin AstraIndexator implementation in this task.
Do not redesign access-zone, TTL, retrieval, chunking, embedding, PostgreSQL canonical-state or Qdrant projection semantics.
Do not silently upgrade images or dependencies.
