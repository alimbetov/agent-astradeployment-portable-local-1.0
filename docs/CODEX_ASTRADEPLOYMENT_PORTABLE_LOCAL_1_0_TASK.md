# Codex Task — AstraDeployment Portable Local Deployment 1.0

## Project

Repository: `alimbetov/agent-astradeployment-portable-local-1.0`

Product milestone:

**AstraDeployment Portable Local Deployment 1.0 — reproducible single-node deployment for AstraVector**

This repository is a deployment product, not the AstraVector source repository.

AstraIndexator is NOT part of version 1.0 because it is not implemented yet.

## Role

Act as a senior DevOps / Platform / SRE engineer designing a reproducible on-prem deployment bundle.

Do not redesign AstraVector internals, retrieval, embeddings, persistence, FIX491 recovery semantics, Qdrant projection semantics, or model loading semantics.

## Primary Goal

A new Mac or Linux server with Docker installed must be able to reproduce a working AstraVector runtime environment from this repository with minimal manual steps.

Target operator flow:

```text
git clone
  ->
cp .env.example .env
  ->
fill secrets
  ->
docker login registry.astrabase.asia
  ->
docker compose up -d
  ->
PostgreSQL/pgvector + Qdrant + AstraVector
  ->
health SERVING
  ->
smoke ingestion
  ->
retrieval returns expected evidence
```

## Current Proven AstraVector Baseline

Use the currently tested AstraVector image as the baseline unless a newer immutable image is explicitly provided by the operator:

```text
registry.astrabase.asia/astravector:sha-1cb6065
```

Recorded digest:

```text
sha256:b0567810b5ea3df752ff8ba559fcf16bc46b245878e798b8888dcf93426ee6ad
```

Known runtime evidence from prior AstraVector validation:

- private registry pull works with reader account;
- Apple Silicon `arm64` image works;
- AstraVector starts with a valid BGE-M3 model cache;
- ONNX Runtime initializes;
- PostgreSQL/pgvector works;
- Qdrant works;
- migrations apply;
- gRPC health reports `SERVING`;
- Russian document ingestion works;
- retrieval returns the expected evidence: `AstraVector хранит каноническое состояние документов в PostgreSQL.`;
- cached restart does not re-download model;
- invalid Nexus password fails closed.

Known current limitations that MUST be documented honestly:

1. Fresh download of the large `model.onnx_data` artifact through the current Nexus/Caddy public path is not fully reliable.
2. HTTP Range/resume is not currently proven end-to-end on the Nexus/Caddy path.
3. Graceful shutdown is not yet proven: `docker stop --time 45` previously ended with `ExitCode=137`, `OOMKilled=false`.

These known limitations do NOT block the goal of creating a reproducible deployment bundle, but they must not be hidden.

## Architecture Contract

The local bundle must provision exactly these runtime components:

```text
AstraDeployment 1.0
├── AstraVector
├── PostgreSQL + pgvector
├── Qdrant
├── BGE-M3 model cache volume
├── Docker network
├── persistent volumes
├── env/secrets contract
├── health checks
├── smoke test
└── recovery/runbook
```

Canonical persistence invariant:

```text
PostgreSQL = canonical state / source of truth
Qdrant     = rebuildable search projection
```

Do not weaken or redefine this.

## Scope

Implement a portable local deployment bundle under:

```text
deploy/local/
```

Expected structure:

```text
deploy/local/
├── docker-compose.astravector.yml
├── .env.example
├── README.md
├── scripts/
│   ├── preflight.sh
│   ├── start.sh
│   ├── health.sh
│   ├── smoke.sh
│   ├── stop.sh
│   └── cleanup.sh
└── recovery/
    └── README.md
```

You may add small supporting files if justified, but keep the bundle simple and auditable.

## Docker Compose Contract

The Compose file must define:

### PostgreSQL

Image:

```text
pgvector/pgvector:pg16
```

Requirements:

- persistent volume;
- healthcheck using `pg_isready`;
- DB name/user/password from `.env`;
- not exposed publicly by default unless a documented local debugging profile requires it;
- AstraVector connects using service DNS name `postgres`.

Suggested local variables:

```text
POSTGRES_DB=astravector
POSTGRES_USER=astravector_app
POSTGRES_PASSWORD=
ASTRAVECTOR_DB_URL=postgres://astravector_app:${POSTGRES_PASSWORD}@postgres:5432/astravector
```

Do not hardcode a real password.

### Qdrant

Image:

```text
qdrant/qdrant:v1.14.1
```

Requirements:

- persistent volume;
- healthcheck based on the actual Qdrant HTTP API;
- AstraVector connects using `http://qdrant:6333`;
- avoid public exposure unless explicitly documented for local debugging.

### AstraVector

Image baseline:

```text
registry.astrabase.asia/astravector:sha-1cb6065
```

Prefer digest-pinned reference if Compose syntax and operator workflow remain practical, for example:

```text
registry.astrabase.asia/astravector@sha256:b0567810b5ea3df752ff8ba559fcf16bc46b245878e798b8888dcf93426ee6ad
```

If tag + digest pinning is awkward, document the exact expected tag and digest and add a preflight verification step.

AstraVector must receive at minimum:

```text
ASTRAVECTOR_DB_URL
ASTRAVECTOR_QDRANT_URL
ASTRAVECTOR_QDRANT_COLLECTION
ASTRAVECTOR_NEXUS_USERNAME
ASTRAVECTOR_NEXUS_PASSWORD
ASTRAVECTOR_MODEL_REPOSITORY_URL
ASTRAVECTOR_MODEL_DIR
ASTRAVECTOR_MODEL_PATH
ASTRAVECTOR_TOKENIZER_PATH
ASTRAVECTOR_MODEL_SHA256
ASTRAVECTOR_MODEL_DATA_SHA256
ASTRAVECTOR_TOKENIZER_SHA256
ASTRAVECTOR_SPARSE_REQUIRED
RUST_LOG
```

Use these verified model hashes:

```text
model.onnx
f84251230831afb359ab26d9fd37d5936d4d9bb5d1d5410e66442f630f24435b

model.onnx_data
1eebfb28493f67bba03ce0ef64bfdc7fc5a3bd9d7493f818bb1d78cd798416b4

tokenizer.json
21106b6d7dab2952c1d496fb21d5dc9db75c28ed361a05f5020bbba27810dd08
```

Model repository URL:

```text
https://nexus.astrabase.asia/repository/astra-models/astravector/bge-m3/baseline-v1
```

The Compose bundle must use a persistent model cache volume mounted to:

```text
/models/bge-m3
```

Normal restart behavior must reuse the cache and avoid re-downloading the 2.2 GB model data file.

For the current smoke baseline set:

```text
ASTRAVECTOR_SPARSE_REQUIRED=false
```

Document why this is needed for the validated local smoke profile and do not silently change production semantics.

## Required Volumes

Define and document at least:

```text
astradeployment-postgres-data
astradeployment-qdrant-data
astradeployment-model-cache
```

Explain their criticality:

- PostgreSQL volume: canonical business/document state; critical for recovery;
- Qdrant volume: rebuildable projection; useful for fast restart but not source of truth;
- model cache: local cache for BGE-M3; can be restored/preloaded to avoid downloading 2.2 GB again.

## `.env.example` Contract

Create a complete `.env.example` with placeholders and safe defaults only.

Example categories:

```text
# AstraVector image
ASTRAVECTOR_IMAGE=registry.astrabase.asia/astravector:sha-1cb6065
ASTRAVECTOR_IMAGE_DIGEST=sha256:b0567810b5ea3df752ff8ba559fcf16bc46b245878e798b8888dcf93426ee6ad

# PostgreSQL
POSTGRES_DB=astravector
POSTGRES_USER=astravector_app
POSTGRES_PASSWORD=

# AstraVector DB
ASTRAVECTOR_DB_URL=

# Qdrant
ASTRAVECTOR_QDRANT_URL=http://qdrant:6333
ASTRAVECTOR_QDRANT_COLLECTION=astravector_v004

# Nexus reader
ASTRAVECTOR_NEXUS_USERNAME=astra-reader
ASTRAVECTOR_NEXUS_PASSWORD=

# Model
ASTRAVECTOR_MODEL_REPOSITORY_URL=https://nexus.astrabase.asia/repository/astra-models/astravector/bge-m3/baseline-v1
ASTRAVECTOR_MODEL_DIR=/models/bge-m3
ASTRAVECTOR_MODEL_PATH=/models/bge-m3/model.onnx
ASTRAVECTOR_TOKENIZER_PATH=/models/bge-m3/tokenizer.json
ASTRAVECTOR_MODEL_SHA256=f84251230831afb359ab26d9fd37d5936d4d9bb5d1d5410e66442f630f24435b
ASTRAVECTOR_MODEL_DATA_SHA256=1eebfb28493f67bba03ce0ef64bfdc7fc5a3bd9d7493f818bb1d78cd798416b4
ASTRAVECTOR_TOKENIZER_SHA256=21106b6d7dab2952c1d496fb21d5dc9db75c28ed361a05f5020bbba27810dd08

ASTRAVECTOR_SPARSE_REQUIRED=false
RUST_LOG=info
```

The actual `.env` file must be gitignored.

## Secrets Rules

Never commit:

- Nexus password;
- PostgreSQL password;
- Docker registry password;
- Qdrant API key;
- AstraVector API key;
- any customer credential.

The repository may document username `astra-reader` as the current reader role, but must not contain the reader password.

Scripts must not echo secrets.

Avoid `set -x` in scripts that can see secrets.

## Preflight Script

Implement `deploy/local/scripts/preflight.sh`.

It should check at minimum:

- Docker installed;
- Docker daemon reachable;
- `docker compose` available;
- host architecture (`arm64` / `amd64`);
- free disk space;
- required `.env` exists;
- required secret variables are non-empty;
- registry login/pullability can be verified without printing credentials;
- exact AstraVector image identity/digest when practical;
- model volume existing/not existing status;
- warning if free disk is insufficient for images + PostgreSQL + Qdrant + model cache.

Do not aggressively delete Docker data in preflight.

## Start Script

Implement `start.sh` as a thin wrapper around Compose.

Expected behavior:

```text
preflight
  ->
docker compose pull
  ->
docker compose up -d
  ->
wait for postgres
  ->
wait for qdrant
  ->
wait for astravector health
```

Do not hide startup failures.

## Health Script

Implement `health.sh`.

It must inspect:

- Compose service state;
- PostgreSQL readiness;
- Qdrant health/API;
- AstraVector gRPC health for service:

```text
astravector.embedding.v1.AstraVectorRuntime
```

Expected healthy state:

```text
SERVING
```

Use a reliable gRPC health client approach. If `grpcurl` is not installed on host, prefer a Dockerized grpcurl client or another self-contained method rather than forcing operators to install many host tools.

## Smoke Script

Implement `smoke.sh` for one minimal functional test.

Use the already proven Russian smoke case.

Canonical text:

```text
AstraVector хранит каноническое состояние документов в PostgreSQL.
Qdrant используется как перестраиваемая поисковая проекция.
Модель BGE-M3 загружается из Nexus и используется для построения эмбеддингов.
```

Canonical question:

```text
Где AstraVector хранит каноническое состояние документов?
```

PASS criterion:

retrieval evidence contains the semantic answer equivalent to:

```text
AstraVector хранит каноническое состояние документов в PostgreSQL.
```

Do not require a generative LLM answer if AstraVector API is retrieval-only.

IMPORTANT:
Do not invent AstraVector API calls.
Inspect the currently documented/proven AstraVector gRPC or REST contracts from the source project documentation or prior evidence and use the real ingestion/search commands.

If the exact API contract cannot be established from available artifacts, stop and mark that part BLOCKED rather than fabricating a request.

## Stop Script

Implement `stop.sh` using Compose stop/down semantics without deleting volumes by default.

Default stop must preserve:

- PostgreSQL data;
- Qdrant data;
- model cache.

Document the known graceful shutdown limitation from the current AstraVector image.

Do not pretend ExitCode 137 is fixed in this repository.

## Cleanup Script

`cleanup.sh` must be safe by default.

Default behavior:

- remove containers/network only;
- preserve all named volumes.

Destructive volume deletion must require explicit opt-in, for example:

```text
./cleanup.sh --delete-data
```

and must print a warning before deleting PostgreSQL canonical state.

## Recovery Runbook

Create `deploy/local/recovery/README.md`.

It must document at least four recovery modes:

### Mode A — Empty Service

Need:

```text
AstraVector image
.env/secrets
Nexus access
```

Creates empty PostgreSQL/Qdrant/model cache.

### Mode B — Fast Local Rebuild

Need:

```text
AstraVector image
.env/secrets
preloaded model cache
```

Avoids fresh 2.2 GB download.

### Mode C — Restore Service With Documents

Need:

```text
PostgreSQL backup/volume
AstraVector image
model cache or Nexus
```

Qdrant may be rebuilt from PostgreSQL according to AstraVector recovery/reconciliation semantics.

### Mode D — Full Fast Restore

Need:

```text
PostgreSQL backup/volume
Qdrant volume
model cache
AstraVector image
```

Fastest recovery path.

Document explicitly:

```text
PostgreSQL is the primary recovery asset.
Qdrant is a rebuildable projection.
Model cache is an operational optimization/cache, not canonical business state.
```

## Backup Guidance

Do not build a full backup product in this task, but document minimally:

- `pg_dump` / PostgreSQL logical backup approach;
- named volume snapshot/export concept;
- Qdrant backup optionality;
- model cache archive/export possibility;
- never rely only on Docker container filesystem.

## Portability

The bundle must work conceptually on:

- Apple Silicon Mac (`arm64`);
- Linux `amd64` server;

BUT do not claim cross-architecture PASS without checking whether the AstraVector image exists for the target architecture.

If current private image is arm64-only, document this explicitly as a portability limitation and define the future requirement for multi-arch publication.

## Resource Guidance

Document practical local minimums.

At minimum account for:

- ~2.2 GB model data;
- AstraVector image;
- PostgreSQL image/data;
- Qdrant image/data;
- runtime RAM for BGE-M3 CPU inference.

Do not invent precise production sizing if not proven. Provide conservative local guidance and label it as guidance, not benchmarked capacity.

## Documentation

`deploy/local/README.md` must be operator-focused.

Required sections:

1. What AstraDeployment 1.0 is.
2. What is included.
3. What is not included (`AstraIndexator`, Kubernetes, Helm).
4. Prerequisites.
5. First installation.
6. `.env` setup.
7. Registry login.
8. Start.
9. Health verification.
10. Smoke test.
11. Restart behavior.
12. Stop.
13. Cleanup.
14. Volumes and persistence.
15. Recovery scenarios.
16. Known limitations.
17. Troubleshooting.
18. Upgrade/image versioning policy.

## Known Limitations Section

Must explicitly list:

### Large model cold download

Fresh network download of `model.onnx_data` (~2.2 GB) may fail on unstable networks/current Nexus-Caddy path.

Recommended operational mitigation:

- preserve model cache volume;
- pre-stage model cache for installations;
- verify SHA256 before use.

Do not remove Nexus support.

### Graceful shutdown

Current tested image previously produced:

```text
docker stop --time 45
ExitCode=137
OOMKilled=false
```

This deployment repository must not claim to have fixed runtime shutdown semantics.

### AstraIndexator

Not included in 1.0.

### Kubernetes

Not part of Portable Local Deployment 1.0. It is a later milestone.

## Validation Gates

Run and record at minimum:

```text
docker compose -f deploy/local/docker-compose.astravector.yml --env-file deploy/local/.env.example config
bash -n deploy/local/scripts/preflight.sh
bash -n deploy/local/scripts/start.sh
bash -n deploy/local/scripts/health.sh
bash -n deploy/local/scripts/smoke.sh
bash -n deploy/local/scripts/stop.sh
bash -n deploy/local/scripts/cleanup.sh
```

If a safe live Docker environment and valid credentials are available, additionally run:

```text
fresh docker pull of AstraVector image
compose up
health
smoke
restart
health again
compose down without volumes
compose up again
health again
```

Do not claim live PASS if these were not actually executed.

## Deliverables

Create at least:

```text
README.md
deploy/local/docker-compose.astravector.yml
deploy/local/.env.example
deploy/local/README.md
deploy/local/scripts/preflight.sh
deploy/local/scripts/start.sh
deploy/local/scripts/health.sh
deploy/local/scripts/smoke.sh
deploy/local/scripts/stop.sh
deploy/local/scripts/cleanup.sh
deploy/local/recovery/README.md
docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_RESULT.md
```

Root README should clearly identify this repository as:

```text
AstraDeployment
Portable Local Deployment 1.0
reproducible single-node deployment for AstraVector
```

## Non-Goals

Do NOT implement in this task:

- AstraIndexator;
- Kubernetes manifests;
- Helm charts;
- HA PostgreSQL;
- clustered Qdrant;
- service mesh;
- Vault;
- operators;
- autoscaling;
- CI/CD for customer environments;
- multi-tenant customer installer;
- web UI;
- changes to AstraVector Rust code;
- changes to Nexus/Caddy infrastructure;
- fixes for graceful shutdown inside AstraVector.

## Future Direction To Preserve

This repository is intended to evolve later into a broader deployment product:

```text
AstraDeployment
├── local        (this milestone)
├── server       (future)
└── kubernetes   (future)
```

Later versions may add AstraIndexator and other platform components without changing the fundamental deployment philosophy.

## Definition of Done

AstraDeployment Portable Local Deployment 1.0 is complete when an operator can follow the repository documentation on a new compatible machine and reproducibly provision the whole local AstraVector runtime environment without relying on undocumented tribal knowledge.

The bundle itself may PASS even if known AstraVector runtime limitations remain, provided those limitations are explicitly documented and the bundle is otherwise valid and reproducible.

## Final Result File

Create:

```text
docs/ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_RESULT.md
```

Record:

- Git SHA;
- files created;
- exact AstraVector image tag/digest;
- static validation results;
- live validation results if executed;
- architecture observed;
- persistence/volume checks;
- secret scan result;
- smoke result if executed;
- known limitations;
- blockers.

Final verdict must be exactly one of:

```text
ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_PASS
ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_FAIL
ASTRADEPLOYMENT_PORTABLE_LOCAL_1_0_BLOCKED
```

PASS requires all bundle-level gates to pass. Live runtime gates may be marked BLOCKED only if the execution environment genuinely prevents them; do not fabricate evidence.

## Execution Order

Before implementation:

1. inspect this repository;
2. read this task completely;
3. inspect the known AstraVector runtime/image contract evidence provided in task context;
4. write a short implementation plan;
5. implement only the deployment bundle scope;
6. run static validation;
7. run live validation when safely possible;
8. create result document;
9. commit all changes to this repository.
