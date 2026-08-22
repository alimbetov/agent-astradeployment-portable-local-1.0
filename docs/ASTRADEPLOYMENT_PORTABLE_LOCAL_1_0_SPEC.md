# AstraDeployment Portable Local Deployment 1.0 — Architecture and Technical Specification

## 1. Product definition

AstraDeployment 1.0 is a deployment product whose purpose is to reproduce a working AstraVector runtime environment on a new single Docker host with minimal operator-specific knowledge.

It is deliberately separate from the AstraVector source repository. AstraVector remains an application image; AstraDeployment owns runtime topology, configuration, persistence, lifecycle, verification and operator documentation.

### Primary operator outcome

A qualified operator with Docker installed must be able to perform:

```text
git clone
→ copy .env.example to .env
→ fill secrets
→ docker login
→ start bundle
→ observe READY/SERVING
→ ingest one test document
→ retrieve expected evidence
```

No Rust toolchain, source build or manual database initialization is required for normal installation.

## 2. Scope of version 1.0

Included:

- AstraVector runtime
- PostgreSQL + pgvector
- Qdrant
- BGE-M3 model cache
- isolated Docker network
- durable volumes
- `.env` configuration contract
- startup orchestration
- health verification
- one deterministic Russian ingestion/retrieval smoke
- stop/cleanup controls
- recovery guidance

Excluded:

- AstraIndexator (not implemented yet)
- Kubernetes and Helm
- HA PostgreSQL/Qdrant
- backup scheduler/product
- public ingress/TLS
- customer IAM integration
- multi-node clustering
- changing AstraVector retrieval/persistence/model semantics

## 3. Source-of-truth boundaries

The deployment MUST preserve the AstraVector persistence invariant:

```text
PostgreSQL
  = canonical application/document state
  = migrations, documents, chunks, bindings, lifecycle, outbox

Qdrant
  = rebuildable search projection

BGE-M3 model cache
  = immutable runtime artifact cache
  = not business state
```

Operational consequence: PostgreSQL is the primary recovery asset. Qdrant can be reconstructed through AstraVector recovery/reconciliation semantics. The model cache can be recreated from a trusted artifact source or restored from a verified cache export.

## 4. Runtime topology

```text
                            localhost operator
                      127.0.0.1 ports only
                               │
               ┌───────────────┼────────────────┐
               │               │                │
            :50051           :8080            :9090
             gRPC          health/REST        metrics
               │               │                │
               └───────────────┴────────────────┘
                               │
                         AstraVector
                               │
             ┌─────────────────┴──────────────────┐
             │                                    │
             ▼                                    ▼
      PostgreSQL + pgvector                     Qdrant
       canonical persistence                search projection
             │                                    │
      durable named volume                  durable named volume

AstraVector
   │
   └── /models/bge-m3
        durable named model-cache volume
        ├── model.onnx
        ├── model.onnx_data
        └── tokenizer.json
```

The PostgreSQL port is not published by default. Qdrant may be bound to `127.0.0.1` for local diagnostics only; it is never bound to `0.0.0.0` in the default bundle.

## 5. Baseline artifact identities

### AstraVector

```text
registry.astrabase.asia/astravector:sha-1cb6065
```

Recorded tested digest:

```text
sha256:b0567810b5ea3df752ff8ba559fcf16bc46b245878e798b8888dcf93426ee6ad
```

The currently proven image is `linux/arm64`. AstraDeployment MUST NOT claim Linux amd64 compatibility until a matching amd64/multi-arch AstraVector image is published and validated. `ASTRAVECTOR_IMAGE` and `ASTRAVECTOR_EXPECTED_DIGEST` remain configurable to support future releases.

### PostgreSQL

```text
pgvector/pgvector:pg16
```

### Qdrant

```text
qdrant/qdrant:v1.14.1
```

### BGE-M3 bundle

Repository:

```text
https://nexus.astrabase.asia/repository/astra-models/astravector/bge-m3/baseline-v1
```

Checksums:

```text
model.onnx
f84251230831afb359ab26d9fd37d5936d4d9bb5d1d5410e66442f630f24435b

model.onnx_data
1eebfb28493f67bba03ce0ef64bfdc7fc5a3bd9d7493f818bb1d78cd798416b4

tokenizer.json
21106b6d7dab2952c1d496fb21d5dc9db75c28ed361a05f5020bbba27810dd08
```

## 6. Model delivery strategy

AstraDeployment treats model distribution and model caching as separate concerns.

### Cold path

If the model cache is empty, the AstraVector image bootstrap downloads the required model artifacts from Nexus using runtime reader credentials and verifies checksums before application startup.

### Warm path — preferred normal restart

If the named model volume already contains valid artifacts, bootstrap verifies them and starts without re-downloading the ~2.2 GB external ONNX data file.

### Recovery/preload path

For customer installations with constrained or unstable connectivity, a verified model-cache volume may be restored/preloaded before AstraVector starts. This is an official recovery path, not a workaround.

Known limitation: fresh public Nexus/Caddy transfer of `model.onnx_data` has shown transport interruptions and HTTP Range/resume has not been proven end-to-end. This does not invalidate the warm-cache deployment contract.

## 7. Configuration contract

Secrets MUST live only in local `.env`, Docker credential storage, or later secret stores. Git stores placeholders and non-secret defaults.

Required operator values:

- `POSTGRES_PASSWORD`
- `ASTRAVECTOR_DB_URL` (password URL-encoded if necessary)
- `ASTRAVECTOR_NEXUS_PASSWORD`

Required runtime identities/non-secret values are pre-populated in `.env.example` and remain overrideable.

Local profile defaults:

```text
ASTRAVECTOR_AUTH_ENABLED=false
ASTRAVECTOR_SPARSE_REQUIRED=false
ASTRAVECTOR_ACCESS_ZONE_REGISTRY_AUTO_CREATE_ON_INGESTION=true
ASTRAVECTOR_ACCESS_ZONE_REGISTRY_AUTO_CREATE_ON_SEARCH=false
```

These are local deployment defaults only and MUST NOT be interpreted as production Kubernetes security policy.

## 8. Persistent volume contract

Stable volume names:

```text
astradeployment-postgres-data
astradeployment-qdrant-data
astradeployment-model-cache
```

Default `stop` and `cleanup` operations preserve all three volumes. Data deletion requires explicit destructive opt-in.

## 9. Startup contract

`start.sh` MUST execute logically:

```text
preflight
→ pull declared images
→ verify AstraVector image identity when possible
→ docker compose up -d
→ wait PostgreSQL healthy
→ wait Qdrant reachable
→ wait AstraVector /ready
→ verify AstraVector gRPC health = SERVING
```

AstraVector is not considered ready when model bootstrap merely finishes. Readiness is application-level.

## 10. Health contract

Required checks:

1. PostgreSQL: `pg_isready` inside the PostgreSQL container.
2. Qdrant: HTTP collection endpoint reachable on the internal Docker network.
3. AstraVector HTTP: `/ready` returns READY.
4. AstraVector gRPC: standard `grpc.health.v1.Health/Check` for service `astravector.embedding.v1.AstraVectorRuntime` returns `SERVING`.

The AstraVector source currently exposes HTTP `/health`, `/ready`, `/api/v1/retrieve` and gRPC reflection/health; the deployment scripts rely only on these real contracts.

## 11. Functional smoke contract

The smoke is a functional retrieval test, not an LLM generation test.

Canonical source text:

```text
AstraVector хранит каноническое состояние документов в PostgreSQL.
Qdrant используется как перестраиваемая поисковая проекция.
Модель BGE-M3 загружается из Nexus и используется для построения эмбеддингов.
```

Question:

```text
Где AstraVector хранит каноническое состояние документов?
```

The smoke MUST use real AstraVector APIs:

1. `AstraVectorIngestionFacade/IndexLogicalDocument`
2. `AstraVectorIngestionFacade/GetDocumentVectorStatus`
3. `AstraVectorV004Control/ActivateDocumentVersion`
4. `POST /api/v1/retrieve` for final retrieval

The test waits until vector publication is ready, activates the version, asks the question and requires response evidence to contain the PostgreSQL fact.

PASS does not require a generated prose answer.

## 12. Shutdown contract

Compose uses a conservative stop grace period. The current AstraVector image previously returned `ExitCode=137` after a 45-second Docker stop despite `OOMKilled=false`. AstraDeployment documents this as an unresolved application-runtime limitation; it does not claim to repair it.

The validation run must record actual stop behavior.

## 13. Security boundaries

Default local installation:

- no real secrets in Git;
- no database/Qdrant ports exposed to non-loopback addresses;
- AstraVector local ports bind only to `127.0.0.1`;
- no `--privileged` containers;
- Nexus reader credential is runtime-only;
- Docker registry authentication is stored by Docker, not the repository;
- scripts never use shell xtrace around secrets.

## 14. Resource guidance

This is guidance, not benchmarked capacity.

For a local CPU validation host, account for:

- >2.2 GB model artifacts plus temporary/cached storage;
- AstraVector, pgvector and Qdrant images;
- database/vector data growth;
- ONNX/BGE-M3 inference memory.

Preflight treats 12 GiB free disk as the minimum warning threshold for an empty model cache and recommends more headroom. It does not automatically delete Docker data.

## 15. Recovery modes

AstraDeployment documents four explicit recovery modes:

- A: empty service — image + secrets + Nexus access;
- B: fast rebuild — image + secrets + verified preloaded model cache;
- C: restore documents — PostgreSQL backup + image + model cache/Nexus, rebuild Qdrant if needed;
- D: full fast restore — PostgreSQL + Qdrant + model cache + image.

## 16. Future mapping to Kubernetes

The local bundle is intentionally a reference deployment contract for future on-prem Kubernetes delivery:

```text
Docker Compose service  → Kubernetes Deployment/StatefulSet
named volume            → PVC
.env                     → ConfigMap + Secret
localhost port           → Service/Ingress policy
health script            → probes
model-cache volume       → model PVC/provisioning lifecycle
```

AstraIndexator will be added later as another service without changing PostgreSQL/Qdrant/model ownership boundaries unless its implemented contract proves otherwise.

## 17. Definition of Done

Implementation DoD (this repository):

- Compose parses successfully;
- `.env.example` is complete and contains no secret value;
- `.env` is gitignored;
- scripts are shell-syntax valid;
- default stop/cleanup preserve volumes;
- health uses real service contracts;
- smoke uses real AstraVector ingestion/status/activation/retrieval APIs;
- documentation clearly states current arm64, large-transfer and shutdown limitations;
- no source build is needed for installation.

Runtime validation DoD (Codex/operator):

- fresh clone works;
- registry pull works;
- exact image identity is recorded;
- PostgreSQL and Qdrant start;
- AstraVector reaches READY/SERVING using valid model cache or successful cold download;
- Russian smoke returns PostgreSQL evidence;
- restart preserves data/model cache;
- stop result is recorded truthfully.

Implementation completion and runtime validation are separate verdicts.
